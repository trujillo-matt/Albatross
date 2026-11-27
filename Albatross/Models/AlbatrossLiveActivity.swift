// AlbatrossLiveActivity.swift
// IMPORTANT: This file must be added to BOTH targets in Xcode File Inspector:
//   ✓ Albatross (main app)
//   ✓ AlbatrossWidgets (widget extension)

import ActivityKit
import Foundation

nonisolated struct AlbatrossLiveActivity: ActivityAttributes {

    // MARK: - ContentState (dynamic — updates with each score entry)

    struct ContentState: Codable, Hashable {
        /// 18 elements. -1 = hole not yet played. Uses sentinel to avoid [Int?] Hashable issues.
        var scores: [Int]
        /// 18 hole pars.
        var pars: [Int]
        /// Number of holes with a score entered (0–18).
        var holesPlayed: Int
        /// Sum of strokes for played holes.
        var totalStrokes: Int
        /// Score relative to par for played holes. Negative = under par, 0 = even, positive = over.
        var scoreToPar: Int
    }

    // MARK: - Static attributes (set once at start, never change)

    /// Full course name — shown in expanded / lock screen view.
    var courseName: String
    /// Short version for the compact Dynamic Island slot (≤14 chars).
    var courseAbbreviation: String
    /// UUID of the round.
    var roundID: UUID
}
