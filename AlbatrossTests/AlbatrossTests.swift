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
