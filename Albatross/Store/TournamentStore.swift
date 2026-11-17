import Combine
import Foundation
import Supabase
import SwiftUI

@MainActor
final class TournamentStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var myTournaments: [Tournament] = []
    @Published private(set) var pendingInvites: [Tournament] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Draft room live state — populated by Realtime subscriptions
    @Published private(set) var captainVotes: [TournamentCaptainVote] = []
    @Published private(set) var draftPlayers: [TournamentPlayer] = []
    @Published private(set) var activeTournament: Tournament? = nil

    // MARK: - Dependencies

    weak var authStore: AuthStore?
    private var draftChannel: RealtimeChannelV2? = nil
    private var standingsChannel: RealtimeChannelV2? = nil

    // MARK: - Load

    func loadMyTournaments() async {
        guard let userID = authStore?.currentProfile?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Tournaments where I am creator or an accepted player
            let created: [Tournament] = try await supabase
                .from("tournaments")
                .select()
                .eq("creator_user_id", value: userID.uuidString)
                .execute()
                .value

            let joined: [Tournament] = try await supabase
                .from("tournaments")
                .select("*, tournament_players!inner(user_id, invite_status)")
                .eq("tournament_players.user_id", value: userID.uuidString)
                .eq("tournament_players.invite_status", value: "accepted")
                .execute()
                .value

            var all = created
            let createdIDs = Set(created.map(\.id))
            all += joined.filter { !createdIDs.contains($0.id) }
            all.sort { $0.createdAt > $1.createdAt }

            // Hydrate each tournament with its sub-tables
            myTournaments = try await withThrowingTaskGroup(of: Tournament.self) { group in
                for t in all {
                    group.addTask { try await self.hydrate(t) }
                }
                var results: [Tournament] = []
                for try await t in group { results.append(t) }
                return results.sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            print("TournamentStore: loadMyTournaments failed — \(error)")
        }
    }

    func loadPendingInvites() async {
        guard let userID = authStore?.currentProfile?.id else { return }
        do {
            // Fetch tournament_players rows where I have a pending invite
            struct PendingRow: Codable {
                var tournamentID: UUID
                enum CodingKeys: String, CodingKey { case tournamentID = "tournament_id" }
            }
            let rows: [PendingRow] = try await supabase
                .from("tournament_players")
                .select("tournament_id")
                .eq("user_id", value: userID.uuidString)
                .eq("invite_status", value: "pending")
                .execute()
                .value

            let ids = rows.map(\.tournamentID)
            guard !ids.isEmpty else { pendingInvites = []; return }

            var invites: [Tournament] = []
            for id in ids {
                let t: Tournament = try await supabase
                    .from("tournaments")
                    .select()
                    .eq("id", value: id.uuidString)
                    .single()
                    .execute()
                    .value
                invites.append(t)
            }
            pendingInvites = invites
        } catch {
            print("TournamentStore: loadPendingInvites failed — \(error)")
        }
    }

    // MARK: - Hydration (load sub-tables)

    private func hydrate(_ tournament: Tournament) async throws -> Tournament {
        var t = tournament
        t.courses = try await loadCourses(tournamentID: t.id)
        t.playerPool = try await loadPlayers(tournamentID: t.id)
        t.teams = try await loadTeams(tournamentID: t.id)
        t.matchups = try await loadMatchups(tournamentID: t.id)
        return t
    }

    private func loadCourses(tournamentID: UUID) async throws -> [TournamentCourse] {
        try await supabase
            .from("tournament_courses")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .order("round_number")
            .execute()
            .value
    }

    private func loadPlayers(tournamentID: UUID) async throws -> [TournamentPlayer] {
        try await supabase
            .from("tournament_players")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .execute()
            .value
    }

    /// Teams in a stable order: Team A first, Team B second.
    /// Callers rely on `teams[0]` being Team A and `teams[1]` being Team B (snake draft
    /// order, captain assignment, standings), and Postgres returns unordered rows without
    /// an ORDER BY. Teams are created as "Team A" then "Team B" in `startDraft` and are
    /// never renamed, so name order is the canonical side order. `id` is a final tie-break
    /// so the result is deterministic even for unexpected data.
    private func loadTeams(tournamentID: UUID) async throws -> [TournamentTeam] {
        let teams: [TournamentTeam] = try await supabase
            .from("tournament_teams")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .order("name")
            .execute()
            .value
        return teams.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func loadMatchups(tournamentID: UUID) async throws -> [TournamentMatchup] {
        try await supabase
            .from("tournament_matchups")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .order("matchup_number")
            .execute()
            .value
    }

    // MARK: - Refresh single tournament

    func reload(_ tournamentID: UUID) async {
        guard let idx = myTournaments.firstIndex(where: { $0.id == tournamentID }) else { return }
        do {
            let base: Tournament = try await supabase
                .from("tournaments")
                .select()
                .eq("id", value: tournamentID.uuidString)
                .single()
                .execute()
                .value
            let hydrated = try await hydrate(base)
            myTournaments[idx] = hydrated
            if activeTournament?.id == tournamentID { activeTournament = hydrated }
        } catch {
            print("TournamentStore: reload failed — \(error)")
        }
    }

    // MARK: - Creation

    func createTournament(
        name: String,
        matchType: TournamentMatchType,
        totalMatches: Int,
        pointsToWin: Double = 9.5,
        courseNames: [String],
        matchTypes: [TournamentMatchType] = []
    ) async throws -> Tournament {
        guard let userID = authStore?.currentProfile?.id else { throw TournamentError.notSignedIn }

        struct NewTournament: Encodable {
            let name: String
            let creator_user_id: String
            let match_type: String
            let total_matches: Int
            let points_to_win: Double
        }

        let created: Tournament = try await supabase
            .from("tournaments")
            .insert(NewTournament(
                name: name,
                creator_user_id: userID.uuidString,
                match_type: matchType.rawValue,
                total_matches: totalMatches,
                points_to_win: pointsToWin
            ))
            .select()
            .single()
            .execute()
            .value

        // Insert course rows, storing per-match format when provided
        for (index, courseName) in courseNames.enumerated() {
            let perMatchType = index < matchTypes.count ? matchTypes[index] : matchType
            struct NewCourse: Encodable {
                let tournament_id: String
                let course_name: String
                let round_number: Int
                let match_type: String
            }
            try await supabase
                .from("tournament_courses")
                .insert(NewCourse(
                    tournament_id: created.id.uuidString,
                    course_name: courseName,
                    round_number: index + 1,
                    match_type: perMatchType.rawValue
                ))
                .execute()
        }

        // Add creator as an accepted admin player
        try await addPlayer(tournamentID: created.id, userID: userID, status: .accepted, isAdmin: true)

        let hydrated = try await hydrate(created)
        myTournaments.insert(hydrated, at: 0)
        return hydrated
    }

    // MARK: - Players / Invites

    func invitePlayer(tournamentID: UUID, userID: UUID) async throws {
        try await addPlayer(tournamentID: tournamentID, userID: userID, status: .pending, isAdmin: false)
        await reload(tournamentID)
    }

    private func addPlayer(
        tournamentID: UUID,
        userID: UUID,
        status: InviteStatus,
        isAdmin: Bool
    ) async throws {
        struct NewPlayer: Encodable {
            let tournament_id: String; let user_id: String; let invite_status: String; let is_admin: Bool
        }
        try await supabase
            .from("tournament_players")
            .insert(NewPlayer(
                tournament_id: tournamentID.uuidString,
                user_id: userID.uuidString,
                invite_status: status.rawValue,
                is_admin: isAdmin
            ))
            .execute()
    }

    func acceptInvite(tournamentID: UUID) async throws {
        guard let userID = authStore?.currentProfile?.id else { return }
        try await updateInviteStatus(tournamentID: tournamentID, userID: userID, status: .accepted)
        await loadPendingInvites()
        await loadMyTournaments()
    }

    func declineInvite(tournamentID: UUID) async throws {
        guard let userID = authStore?.currentProfile?.id else { return }
        try await updateInviteStatus(tournamentID: tournamentID, userID: userID, status: .declined)
        pendingInvites.removeAll { $0.id == tournamentID }
    }

    func deleteTournament(_ tournament: Tournament) async throws {
        try await supabase
            .from("tournaments")
            .delete()
            .eq("id", value: tournament.id.uuidString)
            .execute()
        myTournaments.removeAll { $0.id == tournament.id }
    }

    private func updateInviteStatus(tournamentID: UUID, userID: UUID, status: InviteStatus) async throws {
        struct Update: Encodable { let invite_status: String }
        try await supabase
            .from("tournament_players")
            .update(Update(invite_status: status.rawValue))
            .eq("tournament_id", value: tournamentID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Draft

    func startDraft(tournamentID: UUID) async throws {
        // Set status to draft
        try await updateTournamentStatus(tournamentID, status: .draft)

        // Create two blank teams
        struct NewTeam: Encodable { let tournament_id: String; let name: String }
        try await supabase.from("tournament_teams")
            .insert(NewTeam(tournament_id: tournamentID.uuidString, name: "Team A"))
            .execute()
        try await supabase.from("tournament_teams")
            .insert(NewTeam(tournament_id: tournamentID.uuidString, name: "Team B"))
            .execute()

        await reload(tournamentID)
    }

    func submitCaptainVote(tournamentID: UUID, nomineeUserIDs: [UUID]) async throws {
        guard let voterID = authStore?.currentProfile?.id else { return }
        struct NewVote: Encodable { let tournament_id: String; let voter_user_id: String; let nominee_user_id: String }
        for nomineeID in nomineeUserIDs.prefix(2) {
            try await supabase.from("tournament_captain_votes")
                .insert(NewVote(
                    tournament_id: tournamentID.uuidString,
                    voter_user_id: voterID.uuidString,
                    nominee_user_id: nomineeID.uuidString
                ))
                .execute()
        }
    }

    /// Tallies votes, assigns top 2 vote-getters as captains of Team A and Team B.
    func finalizeCaptains(tournamentID: UUID) async throws {
        let votes: [TournamentCaptainVote] = try await supabase
            .from("tournament_captain_votes")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .execute()
            .value

        // Count votes per nominee
        var tally: [UUID: Int] = [:]
        for v in votes { tally[v.nomineeUserID, default: 0] += 1 }
        let sorted = tally.sorted { $0.value > $1.value }.map(\.key)
        guard sorted.count >= 2 else { throw TournamentError.notEnoughVotes }

        let teams = try await loadTeams(tournamentID: tournamentID)
        guard teams.count >= 2 else { throw TournamentError.teamsNotCreated }

        struct TeamUpdate: Encodable { let captain_user_id: String }
        try await supabase.from("tournament_teams")
            .update(TeamUpdate(captain_user_id: sorted[0].uuidString))
            .eq("id", value: teams[0].id.uuidString)
            .execute()
        try await supabase.from("tournament_teams")
            .update(TeamUpdate(captain_user_id: sorted[1].uuidString))
            .eq("id", value: teams[1].id.uuidString)
            .execute()

        await reload(tournamentID)
    }

    func draftPick(tournamentID: UUID, captainUserID: UUID, pickedPlayerID: UUID) async throws {
        let teams = try await loadTeams(tournamentID: tournamentID)
        guard let team = teams.first(where: { $0.captainUserID == captainUserID }) else {
            throw TournamentError.notACaptain
        }
        try await assignPlayer(tournamentID: tournamentID, playerID: pickedPlayerID, teamID: team.id)
    }

    func overrideDraftAssignment(tournamentID: UUID, playerID: UUID, newTeamID: UUID) async throws {
        try await assignPlayer(tournamentID: tournamentID, playerID: playerID, teamID: newTeamID)
    }

    private func assignPlayer(tournamentID: UUID, playerID: UUID, teamID: UUID) async throws {
        struct Update: Encodable { let team_id: String }
        try await supabase.from("tournament_players")
            .update(Update(team_id: teamID.uuidString))
            .eq("tournament_id", value: tournamentID.uuidString)
            .eq("user_id", value: playerID.uuidString)
            .execute()
    }

    func startTournament(tournamentID: UUID) async throws {
        try await updateTournamentStatus(tournamentID, status: .active)

        // Create all matchups (one per totalMatches)
        guard let tournament = myTournaments.first(where: { $0.id == tournamentID }),
              tournament.teams.count == 2 else { throw TournamentError.teamsNotCreated }

        let teamA = tournament.teams[0]
        let teamB = tournament.teams[1]

        struct NewMatchup: Encodable {
            let tournament_id: String; let matchup_number: Int
            let team_a_id: String; let team_b_id: String
            let match_type: String
        }
        for i in 1...max(1, tournament.totalMatches) {
            // Use the per-course format if set, otherwise fall back to the tournament default
            let courseMatchType = tournament.courses
                .first(where: { $0.roundNumber == i })?
                .matchType ?? tournament.matchType
            try await supabase.from("tournament_matchups")
                .insert(NewMatchup(
                    tournament_id: tournamentID.uuidString,
                    matchup_number: i,
                    team_a_id: teamA.id.uuidString,
                    team_b_id: teamB.id.uuidString,
                    match_type: courseMatchType.rawValue
                ))
                .execute()
        }
        await reload(tournamentID)
    }

    // MARK: - Matchups

    func setMatchupPairings(
        matchupID: UUID,
        teamAPlayerIDs: [UUID],
        teamBPlayerIDs: [UUID]
    ) async throws {
        struct Update: Encodable {
            let team_a_player_ids: [String]
            let team_b_player_ids: [String]
            let status: String
        }
        try await supabase.from("tournament_matchups")
            .update(Update(
                team_a_player_ids: teamAPlayerIDs.map(\.uuidString),
                team_b_player_ids: teamBPlayerIDs.map(\.uuidString),
                status: MatchupStatus.active.rawValue
            ))
            .eq("id", value: matchupID.uuidString)
            .execute()
    }

    func recordMatchupRound(matchupID: UUID, roundID: UUID, userID: UUID) async throws {
        struct NewMatchupRound: Encodable {
            let matchup_id: String; let round_id: String; let user_id: String
        }
        try await supabase.from("tournament_matchup_rounds")
            .upsert(NewMatchupRound(
                matchup_id: matchupID.uuidString,
                round_id: roundID.uuidString,
                user_id: userID.uuidString
            ))
            .execute()
    }

    func loadMatchupRounds(matchupID: UUID) async throws -> [TournamentMatchupRound] {
        try await supabase
            .from("tournament_matchup_rounds")
            .select()
            .eq("matchup_id", value: matchupID.uuidString)
            .execute()
            .value
    }

    /// Fetches all rounds linked to a matchup via tournament_matchup_rounds,
    /// then pulls the full round rows from the rounds table.
    func fetchRoundsForMatchup(matchupID: UUID) async -> [Round] {
        do {
            let links: [TournamentMatchupRound] = try await supabase
                .from("tournament_matchup_rounds")
                .select()
                .eq("matchup_id", value: matchupID.uuidString)
                .execute()
                .value

            guard !links.isEmpty else { return [] }

            struct RoundRow: Codable {
                var id: UUID
                var userID: UUID
                var courseName: String
                var date: Date
                var scores: [Int?]
                var status: String
                var coursePars: [Int]?
                var courseHandicaps: [Int]?
                var courseYardages: [Int]?
                var courseRating: Double?
                var slopeRating: Int?
                var matchupID: UUID?
                var courseLogoFilename: String?
                var updatedAt: Date

                enum CodingKeys: String, CodingKey {
                    case id
                    case userID              = "user_id"
                    case courseName          = "course_name"
                    case date
                    case scores
                    case status
                    case coursePars          = "course_pars"
                    case courseHandicaps     = "course_handicaps"
                    case courseYardages      = "course_yardages"
                    case courseRating        = "course_rating"
                    case slopeRating         = "slope_rating"
                    case matchupID           = "matchup_id"
                    case courseLogoFilename  = "course_logo_filename"
                    case updatedAt           = "updated_at"
                }
            }

            let roundIDs = links.map(\.roundID).map(\.uuidString)
            let rows: [RoundRow] = try await supabase
                .from("rounds")
                .select()
                .in("id", values: roundIDs)
                .execute()
                .value

            return rows.map { row in
                Round(
                    id: row.id,
                    courseName: row.courseName,
                    date: row.date,
                    scores: row.scores,
                    status: RoundStatus(rawValue: row.status) ?? .inProgress,
                    coursePars: row.coursePars,
                    courseHandicaps: row.courseHandicaps,
                    courseYardages: row.courseYardages,
                    courseRating: row.courseRating,
                    slopeRating: row.slopeRating,
                    tournamentMatchupID: row.matchupID,
                    courseLogoFilename: row.courseLogoFilename
                )
            }
        } catch {
            print("TournamentStore: fetchRoundsForMatchup failed — \(error)")
            return []
        }
    }

    func calculateAndSaveMatchupResult(
        matchup: TournamentMatchup,
        teamARounds: [Round],
        teamBRounds: [Round]
    ) async throws {
        let points = calculateMatchPoints(
            matchType: matchup.matchType,
            teamARounds: teamARounds,
            teamBRounds: teamBRounds
        )
        let result: MatchResult = points.teamA > points.teamB ? .teamAWin
                                : points.teamB > points.teamA ? .teamBWin
                                : .tie

        struct Update: Encodable {
            let status: String; let result: String
            let points_team_a: Double; let points_team_b: Double
        }
        try await supabase.from("tournament_matchups")
            .update(Update(
                status: MatchupStatus.complete.rawValue,
                result: result.rawValue,
                points_team_a: points.teamA,
                points_team_b: points.teamB
            ))
            .eq("id", value: matchup.id.uuidString)
            .execute()

        // Check if tournament is complete
        if let tournament = myTournaments.first(where: { $0.id == matchup.tournamentID }) {
            let updatedMatchups = try await loadMatchups(tournamentID: tournament.id)
            let totalA = updatedMatchups.map(\.pointsTeamA).reduce(0, +)
            let totalB = updatedMatchups.map(\.pointsTeamB).reduce(0, +)
            if totalA >= tournament.pointsToWin || totalB >= tournament.pointsToWin {
                try await updateTournamentStatus(tournament.id, status: .complete)
            }
        }
        await reload(matchup.tournamentID)
    }

    // MARK: - Standings

    func standings(for tournament: Tournament) -> TournamentStandings? {
        guard tournament.teams.count == 2 else { return nil }
        let teamA = tournament.teams[0]
        let teamB = tournament.teams[1]
        let pointsA = tournament.matchups.map(\.pointsTeamA).reduce(0, +)
        let pointsB = tournament.matchups.map(\.pointsTeamB).reduce(0, +)
        return TournamentStandings(
            teamA: teamA,
            teamB: teamB,
            pointsTeamA: pointsA,
            pointsTeamB: pointsB,
            pointsToWin: tournament.pointsToWin
        )
    }

    // MARK: - Helpers

    private func updateTournamentStatus(_ id: UUID, status: TournamentStatus) async throws {
        struct Update: Encodable { let status: String; let updated_at: String }
        try await supabase.from("tournaments")
            .update(Update(status: status.rawValue, updated_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Realtime — Draft Room

    func subscribeToDraftRoom(tournamentID: UUID) async {
        let channelName = "tournament-draft-\(tournamentID.uuidString)"
        let channel = supabase.realtimeV2.channel(channelName)

        _ = channel.onPostgresChange(
            InsertAction.self,
            table: "tournament_captain_votes",
            filter: "tournament_id=eq.\(tournamentID.uuidString)"
        ) { [weak self] _ in
            Task { await self?.reloadCaptainVotes(tournamentID: tournamentID) }
        }

        _ = channel.onPostgresChange(
            UpdateAction.self,
            table: "tournament_players",
            filter: "tournament_id=eq.\(tournamentID.uuidString)"
        ) { [weak self] _ in
            Task { await self?.reloadDraftPlayers(tournamentID: tournamentID) }
        }

        _ = channel.onPostgresChange(
            UpdateAction.self,
            table: "tournaments",
            filter: "id=eq.\(tournamentID.uuidString)"
        ) { [weak self] _ in
            Task { await self?.reload(tournamentID) }
        }

        try? await channel.subscribeWithError()
        draftChannel = channel

        // Load initial state
        await reloadCaptainVotes(tournamentID: tournamentID)
        await reloadDraftPlayers(tournamentID: tournamentID)
    }

    func unsubscribeFromDraftRoom() async {
        await draftChannel?.unsubscribe()
        draftChannel = nil
    }

    private func reloadCaptainVotes(tournamentID: UUID) async {
        do {
            captainVotes = try await supabase
                .from("tournament_captain_votes")
                .select()
                .eq("tournament_id", value: tournamentID.uuidString)
                .execute()
                .value
        } catch {
            print("TournamentStore: reloadCaptainVotes failed — \(error)")
        }
    }

    private func reloadDraftPlayers(tournamentID: UUID) async {
        do {
            draftPlayers = try await loadPlayers(tournamentID: tournamentID)
        } catch {
            print("TournamentStore: reloadDraftPlayers failed — \(error)")
        }
    }

    // MARK: - Realtime — Standings

    func subscribeToStandings(tournamentID: UUID) async {
        let channelName = "tournament-standings-\(tournamentID.uuidString)"
        let channel = supabase.realtimeV2.channel(channelName)

        _ = channel.onPostgresChange(
            UpdateAction.self,
            table: "tournament_matchups",
            filter: "tournament_id=eq.\(tournamentID.uuidString)"
        ) { [weak self] _ in
            Task { await self?.reload(tournamentID) }
        }

        try? await channel.subscribeWithError()
        standingsChannel = channel
    }

    func unsubscribeFromStandings() async {
        await standingsChannel?.unsubscribe()
        standingsChannel = nil
    }
}

// MARK: - Errors

enum TournamentError: LocalizedError {
    case notSignedIn
    case notEnoughVotes
    case teamsNotCreated
    case notACaptain

    var errorDescription: String? {
        switch self {
        case .notSignedIn:     return "You must be signed in."
        case .notEnoughVotes:  return "Not enough votes to determine captains."
        case .teamsNotCreated: return "Teams have not been created yet."
        case .notACaptain:     return "You are not a captain in this tournament."
        }
    }
}
