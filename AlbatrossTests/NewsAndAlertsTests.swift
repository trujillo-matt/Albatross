import Foundation
import Testing
@testable import Albatross

/// The words of a news alert, the forecast rules, and the Live Activity summaries.
struct NewsStoryTests {

    private func demoItems() -> (Tournament, [TournamentNewsItem]) {
        let tournament = TournamentDemo.makeTournament()
        return (tournament, TournamentDemo.makeNews(for: tournament, cards: [:]))
    }

    @Test func birdieNamesThePlayerTheTeamTheMatchAndTheOpponent() throws {
        let (tournament, items) = demoItems()
        let birdie = try #require(items.first { $0.kind == "birdie" && $0.headline.contains("Alex Kim") })
        let story = NewsStoryWriter.story(for: birdie, in: [tournament])
        #expect(story.title == "Alex Kim birdies the 4th")
        #expect(story.body.contains("for Team Alex"))
        #expect(story.body.contains("against"))
    }

    @Test func correctedScoreSaysWhatChanged() throws {
        let (tournament, items) = demoItems()
        let change = try #require(items.first { $0.kind == "score_change" && $0.headline.contains("Sam Rhodes") })
        let story = NewsStoryWriter.story(for: change, in: [tournament])
        #expect(story.title == "Score corrected for Sam Rhodes")
        #expect(story.body.contains("changing a 5 to a 4"))
        #expect(story.body.contains("recalculated"))
    }

    @Test func finishedMatchNamesBothSidesAndThePoint() throws {
        let (tournament, items) = demoItems()
        let result = try #require(items.first { $0.kind == "match_result" })
        let story = NewsStoryWriter.story(for: result, in: [tournament])
        #expect(story.body.contains("point toward the Reynolds Cup") || story.body.contains("half a point"))
    }

    @Test func standingIsOnlyQuotedWhileItIsFresh() throws {
        let tournament = TournamentDemo.makeTournament()
        let fresh = try #require(TournamentDemo.freshNewsItem(for: [tournament]))
        let status = TournamentDemo.liveStatuses(for: tournament)
        let now = Date()
        let soon = NewsStoryWriter.story(for: fresh, in: [tournament], liveStatus: status, now: now)
        #expect(soon.body.contains("through"))
        let later = NewsStoryWriter.story(for: fresh, in: [tournament], liveStatus: status, now: now.addingTimeInterval(20 * 60))
        #expect(!later.body.contains("through"))
    }

    @Test func unknownTournamentFallsBackToTheDatabaseHeadline() {
        let item = TournamentNewsItem(id: UUID(), tournamentID: UUID(), kind: "birdie", headline: "Someone made a birdie", createdAt: Date())
        let story = NewsStoryWriter.story(for: item, in: [])
        #expect(story.title == "Someone made a birdie")
    }

    @Test func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23].map(NewsStoryWriter.ordinal)
                == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd"])
    }
}

struct ForecastRulesTests {

    @Test func rainIsLikelyAtEvenOdds() {
        #expect(!ForecastRules.isRainLikely(chance: 0.49))
        #expect(ForecastRules.isRainLikely(chance: 0.5))
    }

    @Test func forecastWindowIsTodayThroughNineDaysOut() throws {
        let now = Date()
        let calendar = Calendar.current
        #expect(ForecastRules.canForecast(now, now: now))
        #expect(ForecastRules.canForecast(try #require(calendar.date(byAdding: .day, value: 9, to: now)), now: now))
        #expect(!ForecastRules.canForecast(try #require(calendar.date(byAdding: .day, value: 10, to: now)), now: now))
        #expect(!ForecastRules.canForecast(try #require(calendar.date(byAdding: .day, value: -1, to: now)), now: now))
    }

    @Test func rainWarningQuotesThePercentage() {
        let warning = ForecastRules.rainWarning(day: 2, course: "Oconee", chance: 0.7)
        #expect(warning.title == "Rain likely on day 2")
        #expect(warning.body.contains("70 percent"))
        #expect(warning.body.contains("Oconee"))
    }
}

struct MatchActivityTests {

    private let attributes = TournamentMatchActivity(
        matchupID: UUID(), tournamentName: "Reynolds Cup", matchNumber: 3, isMatchPlay: true,
        teamAName: "Team Matt", teamBName: "Team Alex", teamAColorHex: "#006747", teamBColorHex: "#731F24",
        teamAPlayers: "Matt", teamBPlayers: "Jordan")

    @Test func summariesRead() {
        typealias State = TournamentMatchActivity.ContentState
        #expect(State(holesPlayed: 0, lead: 0, finished: false).summary(for: attributes) == "Not started")
        #expect(State(holesPlayed: 5, lead: 1, finished: false).summary(for: attributes) == "Team Matt 1 up thru 5")
        #expect(State(holesPlayed: 9, lead: -2, finished: false).summary(for: attributes) == "Team Alex 2 up thru 9")
        #expect(State(holesPlayed: 9, lead: 0, finished: false).summary(for: attributes) == "All square thru 9")
        #expect(State(holesPlayed: 18, lead: 1, finished: true).summary(for: attributes) == "Team Matt won")
        #expect(State(holesPlayed: 18, lead: 0, finished: true).summary(for: attributes) == "Halved")
    }

    @Test func strokeFormatsSayAheadNotUp() {
        var stroke = attributes
        stroke.isMatchPlay = false
        let state = TournamentMatchActivity.ContentState(holesPlayed: 6, lead: 3, finished: false)
        #expect(state.summary(for: stroke) == "Team Matt by 3 thru 6")
    }

    @Test func shortLeadFitsTheIsland() {
        typealias State = TournamentMatchActivity.ContentState
        #expect(State(holesPlayed: 4, lead: -3, finished: false).shortLead == "3 UP")
        #expect(State(holesPlayed: 4, lead: 0, finished: false).shortLead == "AS")
        #expect(State(holesPlayed: 18, lead: 1, finished: true).shortLead == "F")
    }

    @Test func contentStateDecodesWhatTheServerSends() throws {
        let json = #"{"holesPlayed":7,"lead":-1,"finished":false}"#
        let state = try JSONDecoder().decode(TournamentMatchActivity.ContentState.self, from: Data(json.utf8))
        #expect(state == .init(holesPlayed: 7, lead: -1, finished: false))
    }
}
