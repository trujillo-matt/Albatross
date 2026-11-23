import Foundation
import Observation

@MainActor
@Observable
final class CourseStore {
    private(set) var allCourses: [Course] = []

    /// Bound to the search field — debounced before filtering
    var searchText: String = "" { didSet { scheduleSearch() } }

    /// Debounced, filtered results — updated ~200ms after typing stops
    private(set) var results: [Course] = []

    /// Courses flagged isPreloaded — shown in the "Suggested" section before any search query
    var preloadedCourses: [Course] {
        allCourses.filter { $0.isPreloaded }
    }

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Courses the user typed in themselves, kept on the phone so they turn up in search next time.
    private static var customCoursesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("customCourses.json")
    }

    init() {
        loadBundle()
        loadCustomCourses()
    }

    /// Filters the courses about 200 ms after the last keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { results = []; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            results = allCourses
                .filter {
                    $0.name.localizedCaseInsensitiveContains(query) ||
                    $0.city.localizedCaseInsensitiveContains(query) ||
                    $0.state.localizedCaseInsensitiveContains(query)
                }
                .prefix(20)
                .map { $0 }
        }
    }

    /// Saves a course entered by hand. A course with the same name is kept as it is.
    @discardableResult
    func addCustomCourse(name: String, pars: [Int]) -> Course? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, pars.count == 18 else { return nil }
        if let existing = allCourses.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let course = Course(
            id: "custom-\(UUID().uuidString)",
            name: trimmed,
            city: "",
            state: "",
            isPreloaded: false,
            holes: pars.enumerated().map { index, par in
                CourseHole(number: index + 1, par: par, handicap: index + 1, yardage: 0)
            }
        )
        allCourses.insert(course, at: 0)
        saveCustomCourses()
        return course
    }

    private func loadCustomCourses() {
        guard let data = try? Data(contentsOf: Self.customCoursesURL),
              let courses = try? JSONDecoder().decode([Course].self, from: data) else { return }
        allCourses.insert(contentsOf: courses, at: 0)
    }

    private func saveCustomCourses() {
        let custom = allCourses.filter { $0.id.hasPrefix("custom-") }
        do {
            try JSONEncoder().encode(custom).write(to: Self.customCoursesURL, options: .atomic)
        } catch {
            print("CourseStore: failed to save custom courses — \(error)")
        }
    }

    private func loadBundle() {
        guard let url = Bundle.main.url(forResource: "courses", withExtension: "json") else {
            print("CourseStore: courses.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            allCourses = try JSONDecoder().decode([Course].self, from: data)
        } catch {
            print("CourseStore: failed to decode courses.json — \(error)")
        }
    }
}
