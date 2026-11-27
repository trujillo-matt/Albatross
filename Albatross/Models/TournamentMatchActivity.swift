// TournamentMatchActivity.swift
// Shared by the app and the widget extension (see membershipExceptions in the project file).

import ActivityKit
import Foundation

/// A tournament match on the lock screen and in the Dynamic Island.
/// The server updates it over push (drain-push-queue), so ContentState's keys must match what that function sends.
nonisolated struct TournamentMatchActivity: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// Holes both sides have scored.
        var holesPlayed: Int
        /// Team A's lead: holes up in match play, strokes ahead in other formats. Negative when team B leads.
        var lead: Int
        var finished: Bool
    }

    var matchupID: UUID
    var tournamentName: String
    var matchNumber: Int
    var isMatchPlay: Bool
    var teamAName: String
    var teamBName: String
    var teamAColorHex: String
    var teamBColorHex: String
    var teamAPlayers: String
    var teamBPlayers: String
}

extension TournamentMatchActivity.ContentState {
    /// "Team Matt 2 up thru 7", "All square thru 9", "Final".
    func summary(for attributes: TournamentMatchActivity) -> String {
        if finished { return lead == 0 ? "Halved" : "\(leaderName(attributes)) won" }
        guard holesPlayed > 0 else { return "Not started" }
        if lead == 0 { return "All square thru \(holesPlayed)" }
        let margin = abs(lead)
        return attributes.isMatchPlay
            ? "\(leaderName(attributes)) \(margin) up thru \(holesPlayed)"
            : "\(leaderName(attributes)) by \(margin) thru \(holesPlayed)"
    }

    /// "2 UP", "AS", "F": the short form for the island.
    var shortLead: String {
        if finished { return "F" }
        if holesPlayed == 0 { return "—" }
        return lead == 0 ? "AS" : "\(abs(lead)) UP"
    }

    func leaderName(_ attributes: TournamentMatchActivity) -> String {
        lead > 0 ? attributes.teamAName : attributes.teamBName
    }
}
