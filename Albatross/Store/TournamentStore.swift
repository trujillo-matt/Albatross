import Combine
import Foundation
import Supabase
import SwiftUI

@MainActor
final class TournamentStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var myTournaments: [Tournament] = []
    @Published private(set) var pendingInvites: [Tournament] = []
    /// Where each match being played stands, by match id. Filled by `refreshLive`.
    @Published private(set) var liveStatus: [UUID: LiveMatchStatus] = [:]
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

    #if DEBUG
    /// Sets live match statuses for the demo.
    func seedLiveForDemo(_ statuses: [UUID: LiveMatchStatus]) {
        liveStatus = statuses
    }

    /// True while the tournament demo data is showing. Loads that would replace it with cloud results are skipped.
    private(set) var isShowingDemo = false

    /// Fills the list with local data. Used by the tournament demo launch argument.
    func seedForDemo(_ tournaments: [Tournament]) {
        isShowingDemo = true
        myTournaments = tournaments
    }
    #endif

    // MARK: - Load

    func loadMyTournaments() async {
        #if DEBUG
        if isShowingDemo { return }
        #endif
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
        #if DEBUG
        if isShowingDemo { return }
        #endif
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
        // Sessions need migration 008. Without it the tournament still loads, just with no sessions.
        t.sessions = (try? await loadSessions(tournamentID: t.id)) ?? []
        return t
    }

    private func loadSessions(tournamentID: UUID) async throws -> [TournamentSession] {
        try await supabase
            .from("tournament_sessions")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .order("day_number")
            .order("session_number")
            .execute()
            .value
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

    /// The players of a tournament, each with the profile (name, username) the screens show.
    /// Profiles come in a second query: a player's row holds only their user id.
    private func loadPlayers(tournamentID: UUID) async throws -> [TournamentPlayer] {
        var players: [TournamentPlayer] = try await supabase
            .from("tournament_players")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .execute()
            .value

        let ids = players.map { $0.userID.uuidString }
        guard !ids.isEmpty else { return players }
        // A failure here leaves the names blank rather than hiding the whole tournament.
        let profiles: [UserProfile] = (try? await supabase
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value) ?? []
        let profilesByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in players.indices {
            players[index].profile = profilesByID[players[index].userID]
        }
        return players
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
        #if DEBUG
        if isShowingDemo { return }
        #endif
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

    /// Creates a tournament of `days` days. How many matches each day has is not known yet:
    /// it comes from the number of players when the tournament starts, so `total_matches`
    /// holds the day count until then and is rewritten by `startTournament`.
    func createTournament(
        name: String,
        matchType: TournamentMatchType,
        days: Int,
        pointsToWin: Double = 0.5,
        courseNames: [String],
        matchTypes: [TournamentMatchType] = [],
        secondSessionTypes: [TournamentMatchType?] = []
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
                total_matches: days,
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

        // One session per day, plus an optional second one (for example a PM format). The database
        // turns these into matches when the tournament starts.
        struct NewSession: Encodable {
            let tournament_id: String
            let day_number: Int
            let session_number: Int
            let label: String?
            let match_type: String
            let course_name: String
        }
        for (index, courseName) in courseNames.enumerated() {
            let first = index < matchTypes.count ? matchTypes[index] : matchType
            let second: TournamentMatchType? = index < secondSessionTypes.count ? secondSessionTypes[index] : nil
            try await supabase
                .from("tournament_sessions")
                .insert(NewSession(
                    tournament_id: created.id.uuidString, day_number: index + 1, session_number: 1,
                    label: second == nil ? nil : "AM", match_type: first.rawValue, course_name: courseName
                ))
                .execute()
            if let second {
                try await supabase
                    .from("tournament_sessions")
                    .insert(NewSession(
                        tournament_id: created.id.uuidString, day_number: index + 1, session_number: 2,
                        label: "PM", match_type: second.rawValue, course_name: courseName
                    ))
                    .execute()
            }
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

    /// Submits exactly 2 distinct nominees in a single insert (all-or-nothing) and refuses
    /// a second ballot from the same voter. Self-nomination is allowed (matches prior behavior).
    /// The database should also enforce this: see docs/migrations/002_tournament_rules.sql.
    func submitCaptainVote(tournamentID: UUID, nomineeUserIDs: [UUID]) async throws {
        guard let voterID = authStore?.currentProfile?.id else { return }
        var nominees: [UUID] = []
        for id in nomineeUserIDs where !nominees.contains(id) { nominees.append(id) }
        guard nominees.count == 2 else { throw TournamentError.invalidBallot }

        let existing: [TournamentCaptainVote] = try await supabase
            .from("tournament_captain_votes")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .eq("voter_user_id", value: voterID.uuidString)
            .execute()
            .value
        guard existing.isEmpty else { throw TournamentError.alreadyVoted }

        struct NewVote: Encodable { let tournament_id: String; let voter_user_id: String; let nominee_user_id: String }
        let rows = nominees.map {
            NewVote(
                tournament_id: tournamentID.uuidString,
                voter_user_id: voterID.uuidString,
                nominee_user_id: $0.uuidString
            )
        }
        // One request with an array body: PostgREST inserts it as a single statement.
        try await supabase.from("tournament_captain_votes")
            .insert(rows)
            .execute()
    }

    /// Tallies votes and assigns the top 2 vote-getters as captains of Team A and Team B,
    /// and places each captain on their own team.
    ///
    /// Ordering is deterministic: votes descending, then user id. If the 2nd and 3rd place
    /// vote totals are tied, this throws `captainTie` and the commissioner must choose the
    /// winner(s) among the tied nominees via `tiebreakWinners`.
    func finalizeCaptains(tournamentID: UUID, tiebreakWinners: [UUID]? = nil) async throws {
        let votes: [TournamentCaptainVote] = try await supabase
            .from("tournament_captain_votes")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .execute()
            .value

        var tally: [UUID: Int] = [:]
        for v in votes { tally[v.nomineeUserID, default: 0] += 1 }
        let ranked = tally.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.uuidString < $1.key.uuidString
        }
        guard ranked.count >= 2 else { throw TournamentError.notEnoughVotes }

        let captains: [UUID]
        let cutoff = ranked[1].value
        let clearlyIn = ranked.filter { $0.value > cutoff }.map(\.key)
        let tied = ranked.filter { $0.value == cutoff }.map(\.key)
        let slots = 2 - clearlyIn.count          // seats still open among the tied group
        if tied.count > slots {
            guard let winners = tiebreakWinners,
                  winners.count == slots,
                  Set(winners).count == slots,
                  winners.allSatisfy({ tied.contains($0) }) else {
                throw TournamentError.captainTie(candidates: tied, slots: slots)
            }
            captains = clearlyIn + winners
        } else {
            captains = Array(ranked.prefix(2).map(\.key))
        }

        let teams = try await loadTeams(tournamentID: tournamentID)
        guard teams.count >= 2 else { throw TournamentError.teamsNotCreated }

        struct TeamUpdate: Encodable { let captain_user_id: String }
        for (index, captainID) in captains.enumerated() {
            try await supabase.from("tournament_teams")
                .update(TeamUpdate(captain_user_id: captainID.uuidString))
                .eq("id", value: teams[index].id.uuidString)
                .execute()
            // Captains play for their own team; they are not part of the draft pool.
            try await assignPlayer(tournamentID: tournamentID, playerID: captainID, teamID: teams[index].id)
        }

        await reload(tournamentID)
    }

    /// Number of picks made so far. Captains are pre-placed on their teams, so they
    /// are excluded from the count that drives snake order.
    nonisolated static func draftPickCount(players: [TournamentPlayer], teams: [TournamentTeam]) -> Int {
        let captainIDs = Set(teams.compactMap(\.captainUserID))
        return players.filter { $0.teamID != nil && !captainIDs.contains($0.userID) }.count
    }

    /// Makes a pick for `captainUserID`. Goes through the `draft_pick` database function, which checks
    /// that it is that captain's turn and that the player is an accepted, undrafted member of the pool.
    /// A direct table update cannot be used here: row-level security only lets the commissioner (or the
    /// player themselves) update tournament_players rows, so a captain's direct update was silently ignored.
    /// Requires docs/migrations/001 and 002 to be applied.
    func draftPick(tournamentID: UUID, captainUserID: UUID, pickedPlayerID: UUID) async throws {
        let teams = try await loadTeams(tournamentID: tournamentID)
        guard teams.contains(where: { $0.captainUserID == captainUserID }) else {
            throw TournamentError.notACaptain
        }
        nonisolated struct Params: Encodable { let p_tournament: String; let p_player: String }
        do {
            try await supabase.rpc("draft_pick", params: Params(
                p_tournament: tournamentID.uuidString,
                p_player: pickedPlayerID.uuidString
            )).execute()
        } catch {
            let message = String(describing: error)
            if message.contains("not your turn") { throw TournamentError.notYourTurn }
            if message.contains("not available") { throw TournamentError.playerUnavailable }
            throw error
        }
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

    /// The database creates every match of every session from the rosters (floor of the smaller team
    /// over the format's side size, extras sit out), sets the points to win, and auto-fills the first lineup.
    func startTournament(tournamentID: UUID) async throws {
        nonisolated struct Params: Encodable { let p_tournament: String }
        try await supabase.rpc("start_tournament", params: Params(p_tournament: tournamentID.uuidString)).execute()
        await reload(tournamentID)
    }

    // MARK: - Matchups

    /// Goes through the `set_pairings` database function so a team captain (not only the commissioner)
    /// can set pairings; the old direct update was creator-only under row-level security and a captain's
    /// attempt was silently ignored. Requires docs/migrations/005 to be applied.
    func setMatchupPairings(
        matchupID: UUID,
        teamAPlayerIDs: [UUID],
        teamBPlayerIDs: [UUID]
    ) async throws {
        nonisolated struct Params: Encodable {
            let p_matchup: String
            let p_team_a: [String]
            let p_team_b: [String]
        }
        try await supabase.rpc("set_pairings", params: Params(
            p_matchup: matchupID.uuidString,
            p_team_a: teamAPlayerIDs.map(\.uuidString),
            p_team_b: teamBPlayerIDs.map(\.uuidString)
        )).execute()
    }

    // MARK: - Sessions and callouts

    func autofillSession(_ session: TournamentSession) async throws {
        nonisolated struct Params: Encodable { let p_session: String }
        try await supabase.rpc("autofill_session", params: Params(p_session: session.id.uuidString)).execute()
        await reload(session.tournamentID)
    }

    /// Swaps lineup for one team. `units` has one entry per match, in match order.
    func setSessionSide(_ session: TournamentSession, teamID: UUID, units: [[UUID]]) async throws {
        nonisolated struct Params: Encodable { let p_session: String; let p_team: String; let p_units: [[String]] }
        try await supabase.rpc("set_session_side", params: Params(
            p_session: session.id.uuidString, p_team: teamID.uuidString,
            p_units: units.map { $0.map(\.uuidString) }
        )).execute()
        await reload(session.tournamentID)
    }

    func openCallouts(_ session: TournamentSession) async throws {
        nonisolated struct Params: Encodable { let p_session: String }
        try await supabase.rpc("open_callouts", params: Params(p_session: session.id.uuidString)).execute()
        await reload(session.tournamentID)
    }

    /// The captain whose turn it is names one of their units and the opposing unit they want to face.
    func makeCallout(_ session: TournamentSession, myUnit: [UUID], theirUnit: [UUID], asAdmin: Bool) async throws {
        nonisolated struct Params: Encodable {
            let p_session: String; let p_my_unit: [String]; let p_their_unit: [String]; let p_override: Bool
        }
        try await supabase.rpc("make_callout", params: Params(
            p_session: session.id.uuidString, p_my_unit: myUnit.map(\.uuidString),
            p_their_unit: theirUnit.map(\.uuidString), p_override: asAdmin
        )).execute()
        await reload(session.tournamentID)
    }

    func passCallout(_ session: TournamentSession, asAdmin: Bool) async throws {
        nonisolated struct Params: Encodable { let p_session: String; let p_override: Bool }
        try await supabase.rpc("pass_callout", params: Params(p_session: session.id.uuidString, p_override: asAdmin)).execute()
        await reload(session.tournamentID)
    }

    // MARK: - Group scoring (one scorer keeps score for everyone in the match)

    /// Volunteer as the scorer (pass your own id), step down (nil), or, for an organizer, assign any player in the
    /// match. Goes through the `set_scorer` database function. Requires docs/migrations/009 to be applied.
    func setScorer(matchupID: UUID, tournamentID: UUID, scorerID: UUID?) async throws {
        nonisolated struct Params: Encodable { let p_matchup: String; let p_scorer: String? }
        try await supabase.rpc("set_scorer", params: Params(
            p_matchup: matchupID.uuidString,
            p_scorer: scorerID?.uuidString
        )).execute()
        await reload(tournamentID)
    }

    /// Creates every player's card for the group (one per side in scramble and alternate shot). Safe to call twice.
    func startGroupScoring(matchupID: UUID, courseName: String, course: Course?) async throws {
        nonisolated struct CoursePayload: Encodable {
            let course_name: String
            let course_id: String?
            let pars: [Int]?
            let handicaps: [Int]?
            let yardages: [Int]?
            let rating: Double?
            let slope: Int?
        }
        nonisolated struct Params: Encodable { let p_matchup: String; let p_course: CoursePayload }
        try await supabase.rpc("start_group_scoring", params: Params(
            p_matchup: matchupID.uuidString,
            p_course: CoursePayload(
                course_name: courseName,
                course_id: course?.id,
                pars: course?.pars,
                handicaps: course?.handicaps,
                yardages: course?.yardages,
                rating: course?.courseRating,
                slope: course?.slopeRating
            )
        )).execute()
    }

    /// Writes one stroke count (1-based hole). The scorer may write any card in the match they score.
    /// `nil` clears the hole, so the null is sent explicitly (the database function has no default for it).
    func setHoleScore(roundID: UUID, hole: Int, strokes: Int?) async throws {
        nonisolated struct Params: Encodable {
            let p_round: String
            let p_hole: Int
            let p_strokes: Int?
            enum CodingKeys: String, CodingKey { case p_round, p_hole, p_strokes }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_round, forKey: .p_round)
                try c.encode(p_hole, forKey: .p_hole)
                try c.encode(p_strokes, forKey: .p_strokes)
            }
        }
        try await supabase.rpc("set_hole_score", params: Params(
            p_round: roundID.uuidString,
            p_hole: hole,
            p_strokes: strokes
        )).execute()
    }

    /// Submits every card in the group together. Only the scorer (or an organizer), and only with all 18 holes entered.
    func finishGroupScoring(matchupID: UUID, tournamentID: UUID) async throws {
        nonisolated struct Params: Encodable { let p_matchup: String }
        try await supabase.rpc("finish_group_scoring", params: Params(p_matchup: matchupID.uuidString)).execute()
        await reload(tournamentID)
    }

    /// Every card for a match, with its owner. Members of the tournament can read all of them.
    func fetchGroupCards(matchupID: UUID) async -> [GroupCard] {
        do {
            let rows: [GroupCard] = try await supabase
                .from("rounds")
                .select()
                .eq("matchup_id", value: matchupID.uuidString)
                .execute()
                .value
            return rows
        } catch {
            print("TournamentStore: fetchGroupCards failed — \(error)")
            return []
        }
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
            let allPlayed = !updatedMatchups.isEmpty && updatedMatchups.allSatisfy { $0.status == .complete }
            // Finish on reaching the target, or once every match is played (covers an even
            // split where neither side reaches the target).
            if totalA >= tournament.pointsToWin || totalB >= tournament.pointsToWin || allPlayed {
                try await updateTournamentStatus(tournament.id, status: .complete)
            }
        }
        await reload(matchup.tournamentID)
    }

    // MARK: - Live

    /// Reloads the tournament and works out where each match being played stands from both sides' scores.
    /// The board calls this every few seconds while it is on screen.
    func refreshLive(for tournamentID: UUID) async {
        #if DEBUG
        if isShowingDemo { return }
        #endif
        await reload(tournamentID)
        guard let tournament = myTournaments.first(where: { $0.id == tournamentID }) else { return }

        var statuses = liveStatus
        for matchup in tournament.matchups {
            guard matchup.status == .active else {
                statuses[matchup.id] = nil
                continue
            }
            let links = (try? await loadMatchupRounds(matchupID: matchup.id)) ?? []
            let allRounds = await fetchRoundsForMatchup(matchupID: matchup.id)
            func roundsOf(_ playerIDs: [UUID]) -> [Round] {
                allRounds.filter { round in
                    links.contains { $0.roundID == round.id && playerIDs.contains($0.userID) }
                }
            }
            statuses[matchup.id] = LiveMatchStatus.from(
                teamARounds: roundsOf(matchup.teamAPlayerIDs),
                teamBRounds: roundsOf(matchup.teamBPlayerIDs),
                matchType: matchup.matchType)
        }
        liveStatus = statuses
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

        _ = channel.onPostgresChange(
            UpdateAction.self,
            table: "tournament_sessions",
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
    case invalidBallot
    case alreadyVoted
    case notYourTurn
    case playerUnavailable
    /// 2nd and 3rd place are tied; the commissioner must pick `slots` of `candidates`.
    case captainTie(candidates: [UUID], slots: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBallot:     return "Pick exactly 2 different nominees."
        case .alreadyVoted:      return "You have already voted."
        case .notYourTurn:       return "It is not your turn to pick."
        case .playerUnavailable: return "That player is not available to draft."
        case .captainTie:        return "The vote is tied for the last captain spot. Choose who becomes captain."
        case .notSignedIn:     return "You must be signed in."
        case .notEnoughVotes:  return "Not enough votes to determine captains."
        case .teamsNotCreated: return "Teams have not been created yet."
        case .notACaptain:     return "You are not a captain in this tournament."
        }
    }
}
