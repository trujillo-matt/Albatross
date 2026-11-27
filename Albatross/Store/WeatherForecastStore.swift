import CoreLocation
import Foundation
import MapKit
import OSLog
import UserNotifications
import WeatherKit

/// The weather for one round of a tournament: the forecast for the day its group tees off.
struct RoundForecast: Identifiable, Equatable {
    let id: UUID                    // the session
    let sessionTitle: String
    let dayNumber: Int
    let courseName: String
    let date: Date
    let condition: String
    let symbolName: String
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
    let rainChance: Double          // 0...1
    let windSpeed: Measurement<UnitSpeed>

    var isRainLikely: Bool { ForecastRules.isRainLikely(chance: rainChance) }
}

/// The judgements about a forecast, kept apart from the network code so they can be tested.
enum ForecastRules {
    /// Rain worth a warning: better than even odds of precipitation.
    static func isRainLikely(chance: Double) -> Bool { chance >= 0.5 }

    /// WeatherKit sees about ten days ahead. A round further out, or already played, has no forecast yet.
    static func canForecast(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let last = calendar.date(byAdding: .day, value: 9, to: today) else { return false }
        return calendar.startOfDay(for: date) >= today && calendar.startOfDay(for: date) <= last
    }

    /// The text of a rain warning for a round.
    static func rainWarning(day: Int, course: String, chance: Double) -> (title: String, body: String) {
        let percent = Int((chance * 100).rounded())
        return ("Rain likely on day \(day)",
                "The forecast for \(course) shows a \(percent) percent chance of rain on day \(day) of your tournament. Pack a rain jacket and check the tee times.")
    }
}

/// Forecasts for the days a tournament is played, from Apple Weather.
/// WeatherKit needs the paid Apple Developer Program and its capability on the app. Without them every call fails, and this
/// store reports `unavailable` so the screen simply leaves the forecast out.
@MainActor
@Observable
final class WeatherForecastStore {
    enum Status: Equatable { case idle, loading, ready, unavailable }

    private(set) var status: Status = .idle
    private(set) var forecasts: [RoundForecast] = []
    /// The Apple Weather mark and legal page. Apple requires both wherever its data is shown.
    private(set) var attribution: WeatherAttribution?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var coordinateCache: [String: [Double]] = [:]
    private let cacheKey = "weatherCourseCoordinates"
    private let alertedKey = "weatherRainAlerted"

    init() {
        coordinateCache = (defaults.dictionary(forKey: cacheKey) as? [String: [Double]]) ?? [:]
    }

    /// Looks up the forecast for every session of the tournament that has a tee time within the forecast window.
    func load(for tournament: Tournament, courses: [Course]) async {
        status = .loading
        var result: [RoundForecast] = []
        do {
            for session in tournament.sortedSessions {
                guard let courseName = session.courseName, !courseName.isEmpty,
                      let teeTime = tournament.teeTimes.filter({ $0.sessionID == session.id }).map(\.teeTime).min(),
                      ForecastRules.canForecast(teeTime),
                      let place = await location(forCourse: courseName, courses: courses) else { continue }
                var calendar = Calendar.current
                if let zone = place.timeZone { calendar.timeZone = zone }
                let daily = try await WeatherService.shared.weather(for: place.location, including: .daily)
                guard let day = daily.forecast.first(where: { calendar.isDate($0.date, inSameDayAs: teeTime) }) else { continue }
                result.append(RoundForecast(
                    id: session.id, sessionTitle: session.title, dayNumber: session.dayNumber, courseName: courseName,
                    date: teeTime, condition: day.condition.description, symbolName: day.symbolName,
                    high: day.highTemperature, low: day.lowTemperature,
                    rainChance: day.precipitationChance, windSpeed: day.wind.speed))
            }
            forecasts = result
            if attribution == nil { attribution = try? await WeatherService.shared.attribution }
            status = .ready
        } catch {
            Log.app.error("WeatherForecastStore: forecast unavailable — \(error)")
            forecasts = []
            status = .unavailable
        }
    }

    /// Rain warnings for rounds within the next day and a half, once each. Used by the background refresh.
    func alertAboutRain(tournaments: [Tournament], courses: [Course]) async {
        guard UserDefaults.standard.object(forKey: NewsAlerts.enabledKey) as? Bool ?? true else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        var alerted = Set(defaults.stringArray(forKey: alertedKey) ?? [])
        for tournament in tournaments where tournament.status == .active {
            await load(for: tournament, courses: courses)
            for forecast in forecasts where forecast.isRainLikely
                && forecast.date.timeIntervalSinceNow > 0 && forecast.date.timeIntervalSinceNow < 36 * 3600
                && !alerted.contains(forecast.id.uuidString) {
                let warning = ForecastRules.rainWarning(day: forecast.dayNumber, course: forecast.courseName, chance: forecast.rainChance)
                let content = UNMutableNotificationContent()
                content.title = warning.title
                content.body = warning.body
                content.sound = .default
                content.threadIdentifier = tournament.id.uuidString
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rain-\(forecast.id)", content: content, trigger: nil))
                alerted.insert(forecast.id.uuidString)
            }
        }
        defaults.set(Array(alerted), forKey: alertedKey)
    }

    // MARK: - Where a course is

    private struct Place { let location: CLLocation; let timeZone: TimeZone? }

    /// Finds a course with Apple Maps, using the city and state when the course list has them. The answer is remembered.
    private func location(forCourse name: String, courses: [Course]) async -> Place? {
        if let cached = coordinateCache[name], cached.count == 2 {
            return Place(location: CLLocation(latitude: cached[0], longitude: cached[1]), timeZone: nil)
        }
        let known = courses.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, known?.city, known?.state].compactMap { $0 }.joined(separator: " ")
        request.resultTypes = .pointOfInterest
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        coordinateCache[name] = [coordinate.latitude, coordinate.longitude]
        defaults.set(coordinateCache, forKey: cacheKey)
        return Place(location: item.location, timeZone: item.timeZone)
    }
}
