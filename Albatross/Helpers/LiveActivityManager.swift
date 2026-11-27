import ActivityKit
import OSLog
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
                let handle = ActivityHandle(activity: existing)
                Task { await Self.end(handle, with: existing.content.state, policy: .immediate) }
                activity = nil
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.app.error("LiveActivityManager: Live Activities not enabled on this device")
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
            Log.app.info("LiveActivityManager: Started — \(newActivity.id)")
        } catch {
            Log.app.error("LiveActivityManager: Failed to start — \(error)")
        }
    }

    func updateActivity(for round: Round) {
        guard round.status == .inProgress else {
            endActivity(for: round)
            return
        }
        guard let activity else {
            startActivity(for: round)
            return
        }
        let state = contentState(for: round)
        let handle = ActivityHandle(activity: activity)
        Task { await Self.update(handle, to: state) }
    }

    func endActivity(for round: Round) {
        guard let activity else { return }
        let finalState = contentState(for: round)
        let handle = ActivityHandle(activity: activity)
        Task {
            // Keep final score visible for 60 seconds after finishing
            await Self.end(handle, with: finalState, policy: .after(.now + 60))
            self.activity = nil
        }
    }

    /// Ends the Live Activity immediately (used when a round is deleted).
    func endActivityImmediately(for round: Round) {
        guard let activity, activity.attributes.roundID == round.id else { return }
        let finalState = contentState(for: round)
        let handle = ActivityHandle(activity: activity)
        Task {
            await Self.end(handle, with: finalState, policy: .immediate)
            self.activity = nil
        }
    }

    // MARK: - Helpers

    /// The Activity is only ever used from the main actor here; the box lets it cross into the async calls.
    private nonisolated struct ActivityHandle: @unchecked Sendable { let activity: Activity<AlbatrossLiveActivity> }

    private nonisolated static func update(_ handle: ActivityHandle, to state: AlbatrossLiveActivity.ContentState) async {
        await handle.activity.update(.init(state: state, staleDate: nil))
    }

    private nonisolated static func end(_ handle: ActivityHandle, with state: AlbatrossLiveActivity.ContentState, policy: ActivityUIDismissalPolicy) async {
        await handle.activity.end(.init(state: state, staleDate: nil), dismissalPolicy: policy)
    }

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
