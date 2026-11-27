import ActivityKit
import Foundation
import OSLog
import Supabase

/// Keeps a Live Activity on the lock screen for each tournament match the signed-in player is in while it is being played.
/// The app updates it whenever it refreshes the standing, and each activity's push token is saved in the cloud so the server
/// can update it while the app is closed (docs/migrations/024).
@MainActor
final class TournamentMatchActivityManager {
    static let shared = TournamentMatchActivityManager()
    private init() {}

    private var activities: [UUID: Activity<TournamentMatchActivity>] = [:]
    private var tokenTasks: [UUID: Task<Void, Never>] = [:]

    /// Starts, updates or ends the activities for the matches `userID` plays in.
    func sync(tournament: Tournament, liveStatus: [UUID: LiveMatchStatus], userID: UUID?) {
        guard let userID else { return }
        adoptRunningActivities()
        for matchup in tournament.matchups where matchup.teamAPlayerIDs.contains(userID) || matchup.teamBPlayerIDs.contains(userID) {
            if matchup.status == .complete {
                end(matchup.id, finalLead: lead(of: matchup))
            } else if let status = liveStatus[matchup.id] {
                let state = TournamentMatchActivity.ContentState(holesPlayed: status.holesPlayed, lead: status.lead, finished: false)
                if let existing = activities[matchup.id] {
                    let handle = ActivityHandle(activity: existing)
                    Task { await Self.update(handle, to: state) }
                } else {
                    start(matchup, in: tournament, state: state)
                }
            }
        }
    }

    // MARK: - Private

    private func start(_ matchup: TournamentMatchup, in tournament: Tournament, state: TournamentMatchActivity.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        func team(_ id: UUID) -> TournamentTeam? { tournament.teams.first { $0.id == id } }
        func names(_ ids: [UUID]) -> String {
            ids.compactMap { id in tournament.playerPool.first { $0.userID == id }?.profile?.displayName }.formatted(.list(type: .and))
        }
        let attributes = TournamentMatchActivity(
            matchupID: matchup.id, tournamentName: tournament.name, matchNumber: matchup.matchupNumber,
            isMatchPlay: matchup.matchType == .matchPlay,
            teamAName: team(matchup.teamAID)?.name ?? "Team A", teamBName: team(matchup.teamBID)?.name ?? "Team B",
            teamAColorHex: team(matchup.teamAID)?.color ?? "#006747", teamBColorHex: team(matchup.teamBID)?.color ?? "#731F24",
            teamAPlayers: names(matchup.teamAPlayerIDs), teamBPlayers: names(matchup.teamBPlayerIDs))
        do {
            let activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: .token)
            track(activity)
        } catch {
            Log.app.error("TournamentMatchActivityManager: could not start — \(error)")
        }
    }

    /// Picks up activities that survived the app being closed, so they are updated rather than duplicated.
    private func adoptRunningActivities() {
        for activity in Activity<TournamentMatchActivity>.activities where activities[activity.attributes.matchupID] == nil {
            track(activity)
        }
    }

    private func track(_ activity: Activity<TournamentMatchActivity>) {
        let matchupID = activity.attributes.matchupID
        activities[matchupID] = activity
        // The token can change while the activity runs; each one is saved so the server always has the current one.
        tokenTasks[matchupID]?.cancel()
        tokenTasks[matchupID] = Task {
            for await data in activity.pushTokenUpdates {
                await Self.register(token: data.map { String(format: "%02x", $0) }.joined(), matchupID: matchupID)
            }
        }
    }

    private func end(_ matchupID: UUID, finalLead: Int) {
        guard let activity = activities[matchupID] else { return }
        let state = TournamentMatchActivity.ContentState(holesPlayed: activity.content.state.holesPlayed, lead: finalLead, finished: true)
        tokenTasks[matchupID]?.cancel()
        tokenTasks[matchupID] = nil
        // Left in the table until it has ended, so the next sync does not start a second one.
        let handle = ActivityHandle(activity: activity)
        Task {
            await Self.end(handle, with: state)
            activities[matchupID] = nil
        }
    }

    private func lead(of matchup: TournamentMatchup) -> Int {
        switch matchup.result {
        case .teamAWin: return 1
        case .teamBWin: return -1
        default: return 0
        }
    }

    /// ActivityKit's Activity is only ever used from the main actor here; the box lets it cross into the async calls.
    private nonisolated struct ActivityHandle: @unchecked Sendable { let activity: Activity<TournamentMatchActivity> }

    private nonisolated static func update(_ handle: ActivityHandle, to state: TournamentMatchActivity.ContentState) async {
        await handle.activity.update(.init(state: state, staleDate: nil))
    }

    private nonisolated static func end(_ handle: ActivityHandle, with state: TournamentMatchActivity.ContentState) async {
        await handle.activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 60))
    }

    private static func register(token: String, matchupID: UUID) async {
        nonisolated struct Params: Encodable { let p_matchup: String; let p_token: String }
        do {
            try await supabase.rpc("register_live_activity_token", params: Params(p_matchup: matchupID.uuidString, p_token: token)).execute()
        } catch {
            Log.app.error("TournamentMatchActivityManager: could not save the push token — \(error)")
        }
    }
}
