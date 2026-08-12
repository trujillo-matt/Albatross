import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<AlbatrossLiveActivity>?

    // MARK: - Public API

    func startActivity(for round: Round) {
        guard round.status == .inProgress else { return }

        // If an activity is already running for this round, update it instead
        if let existing = activity {
            if existing.attributes.roundID == round.id {
                updateActivity(for: round)
                return
            } else {
                // Different round — end the old one first
                Task { await existing.end(ActivityContent(state: existing.content.state, staleDate: nil), dismissalPolicy: .immediate) }
                activity = nil
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("LiveActivityManager: Live Activities not enabled on this device")
            return
        }

        let attributes = AlbatrossLiveActivity(
            courseName: round.courseName,
            courseAbbreviation: abbreviated(round.courseName),
            roundID: round.id
        )

        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState(for: round), staleDate: nil),
                pushType: nil
            )
            activity = newActivity
            print("LiveActivityManager: Started — \(newActivity.id)")
        } catch {
            print("LiveActivityManager: Failed to start — \(error)")
        }
    }

    func updateActivity(for round: Round) {
        guard round.status == .inProgress else {
            endActivity(for: round)
            return
        }
        guard activity != nil else {
            startActivity(for: round)
            return
        }
        let state = contentState(for: round)
        Task {
            await activity?.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity(for round: Round) {
        guard let activity else { return }
        let finalState = contentState(for: round)
        Task {
            // Keep final score visible for 60 seconds after finishing
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 60)
            )
            self.activity = nil
        }
    }

    /// Ends the Live Activity immediately (used when a round is deleted).
    func endActivityImmediately(for round: Round) {
        guard let activity, activity.attributes.roundID == round.id else { return }
        let finalState = contentState(for: round)
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            self.activity = nil
        }
    }

    // MARK: - Helpers

    private func contentState(for round: Round) -> AlbatrossLiveActivity.ContentState {
        let pars = round.effectivePars
        let sentinelScores = round.scores.map { $0 ?? -1 }

        var scoreToPar = 0
        for (index, score) in round.scores.enumerated() {
            if let s = score {
                scoreToPar += s - pars[index]
            }
        }

        return AlbatrossLiveActivity.ContentState(
            scores: sentinelScores,
            pars: pars,
            holesPlayed: round.holesPlayed,
            totalStrokes: round.totalScore,
            scoreToPar: scoreToPar
        )
    }

    private func abbreviated(_ name: String) -> String {
        let replacements: [(String, String)] = [
            ("Golf Links", "GL"),
            ("Golf Course", "GC"),
            ("Golf Club", "GC"),
            ("Country Club", "CC"),
            ("National", "Natl"),
            ("Beach", "Bch"),
            ("Links", "Lnks"),
        ]
        var result = name
        for (full, abbr) in replacements {
            result = result.replacingOccurrences(of: full, with: abbr)
        }
        if result.count > 14 {
            result = String(result.prefix(13)) + "…"
        }
        return result
    }
}
