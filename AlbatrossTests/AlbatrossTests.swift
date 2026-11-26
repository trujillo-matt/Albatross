//
//  AlbatrossTests.swift
//  AlbatrossTests
//

import Foundation
import Observation
import Testing
@testable import Albatross

@MainActor
struct ObservableStoreTests {

    @Test func cardAppearanceSavesEachChange() {
        let suite = "albatross.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let appearance = CardAppearance(defaults: defaults)
        appearance.paper = .inherit
        appearance.tracksPuttsAndGreens = false

        #expect(defaults.string(forKey: "cardPaper") == PaperStock.inherit.rawValue)
        #expect(defaults.object(forKey: "cardTracksPutts") as? Bool == false)
        // A second appearance reads back what the first saved.
        let reloaded = CardAppearance(defaults: defaults)
        #expect(reloaded.paper == .inherit)
        #expect(reloaded.tracksPuttsAndGreens == false)
    }

    @Test func viewsAreToldWhenAStoredValueChanges() {
        let appearance = CardAppearance(defaults: UserDefaults(suiteName: "albatross.tests.\(UUID().uuidString)")!)
        var notified = false
        withObservationTracking {
            _ = appearance.tracksPuttsAndGreens
        } onChange: {
            notified = true
        }
        appearance.tracksPuttsAndGreens.toggle()
        #expect(notified)
    }

    @Test func aViewReadingOneValueIsNotToldAboutAnother() {
        let appearance = CardAppearance(defaults: UserDefaults(suiteName: "albatross.tests.\(UUID().uuidString)")!)
        var notified = false
        withObservationTracking {
            _ = appearance.tracksPuttsAndGreens
        } onChange: {
            notified = true
        }
        appearance.paper = .inherit
        #expect(!notified)
    }

    @Test func courseSearchWaitsForTypingToStopThenFilters() async throws {
        let store = CourseStore()
        guard let course = store.allCourses.first(where: { $0.id.hasPrefix("custom-") == false }) else { return }
        store.searchText = String(course.name.prefix(4))
        #expect(store.results.isEmpty)                       // nothing until the typing pauses
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.results.contains(where: { $0.id == course.id }))
        store.searchText = ""
        #expect(store.results.isEmpty)                       // clearing the field clears the results at once
    }
}

struct ShambleFormatTests {

    @Test func shambleIsAPairsFormatWithACardPerPlayer() {
        #expect(TournamentMatchType.shamble.playersPerSide == 2)
        #expect(TournamentMatchType.shamble.displayName == "Shamble")
        #expect(TournamentMatchType.shamble.sideDescription == "Pairs")
    }

    @Test func theDatabaseValueDecodes() throws {
        let decoded = try JSONDecoder().decode([TournamentMatchType].self, from: Data(#"["shamble","best_ball"]"#.utf8))
        #expect(decoded == [.shamble, .bestBall])
    }

    @Test func shambleLiveStatusCountsStrokesLikeBestBall() {
        func round(_ strokes: Int) -> Round {
            var round = Round(courseName: "Test")
            round.scores = Array(repeating: strokes, count: 18).map { Optional($0) }
            return round
        }
        // A's best score each hole is 4, B's is 5: A leads by 18 strokes over 18 holes.
        let status = LiveMatchStatus.from(teamARounds: [round(4), round(6)], teamBRounds: [round(5), round(5)], matchType: .shamble)
        #expect(status.holesPlayed == 18)
        #expect(status.lead == 18)
    }
}
