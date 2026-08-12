import Foundation

// MARK: - Enums

enum TournamentStatus: String, Codable {
    case setup    = "setup"
    case draft    = "draft"
    case active   = "active"
    case complete = "complete"
}

enum TournamentMatchType: String, Codable, CaseIterable {
    case scramble   = "scramble"
    case bestBall   = "best_ball"
    case matchPlay  = "match_play"
    case strokePlay = "stroke_play"

    var displayName: String {
        switch self {
        case .scramble:   return "Scramble"
        case .bestBall:   return "Best Ball"
        case .matchPlay:  return "Match Play"
        case .strokePlay: return "Stroke Play"
        }
    }
}

enum InviteStatus: String, Codable {
    case pending  = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

enum MatchupStatus: String, Codable {
    case pending  = "pending"
    case active   = "active"
    case complete = "complete"
}

enum MatchResult: String, Codable {
    case teamAWin = "team_a_win"
    case teamBWin = "team_b_win"
    case tie      = "tie"
}

// MARK: - Tournament Course

struct TournamentCourse: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var courseName: String
    var roundNumber: Int
    var matchType: TournamentMatchType?

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID  = "tournament_id"
        case courseName    = "course_name"
        case roundNumber   = "round_number"
        case matchType     = "match_type"
    }
}

// MARK: - TournamentPlayer

struct TournamentPlayer: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var userID: UUID
    var teamID: UUID?
    var inviteStatus: InviteStatus
    var isAdmin: Bool
    var draftPosition: Int?

    /// Populated client-side by joining against profiles — not a DB column
    var profile: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID  = "tournament_id"
        case userID        = "user_id"
        case teamID        = "team_id"
        case inviteStatus  = "invite_status"
        case isAdmin       = "is_admin"
        case draftPosition = "draft_position"
    }
}

// MARK: - TournamentTeam

struct TournamentTeam: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var name: String
    var captainUserID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID  = "tournament_id"
        case name
        case captainUserID = "captain_user_id"
    }
}

// MARK: - CaptainVote

struct TournamentCaptainVote: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var voterUserID: UUID
    var nomineeUserID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID   = "tournament_id"
        case voterUserID    = "voter_user_id"
        case nomineeUserID  = "nominee_user_id"
    }
}

// MARK: - TournamentMatchup

struct TournamentMatchup: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var matchupNumber: Int
    var teamAID: UUID
    var teamBID: UUID
    var teamAPlayerIDs: [UUID]
    var teamBPlayerIDs: [UUID]
    var matchType: TournamentMatchType
    var status: MatchupStatus
    var result: MatchResult?
    var pointsTeamA: Double
    var pointsTeamB: Double

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID   = "tournament_id"
        case matchupNumber  = "matchup_number"
        case teamAID        = "team_a_id"
        case teamBID        = "team_b_id"
        case teamAPlayerIDs = "team_a_player_ids"
        case teamBPlayerIDs = "team_b_player_ids"
        case matchType      = "match_type"
        case status
        case result
        case pointsTeamA    = "points_team_a"
        case pointsTeamB    = "points_team_b"
    }
}

// MARK: - TournamentMatchupRound

struct TournamentMatchupRound: Identifiable, Codable {
    var id: UUID
    var matchupID: UUID
    var roundID: UUID
    var userID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case matchupID = "matchup_id"
        case roundID   = "round_id"
        case userID    = "user_id"
    }
}

// MARK: - Tournament (root)

struct Tournament: Identifiable, Codable {
    var id: UUID
    var name: String
    var creatorUserID: UUID
    var status: TournamentStatus
    var matchType: TournamentMatchType
    var totalMatches: Int
    var pointsToWin: Double
    var createdAt: Date
    var updatedAt: Date

    /// Populated client-side from related table fetches
    var courses: [TournamentCourse] = []
    var playerPool: [TournamentPlayer] = []
    var teams: [TournamentTeam] = []
    var matchups: [TournamentMatchup] = []

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorUserID = "creator_user_id"
        case status
        case matchType     = "match_type"
        case totalMatches  = "total_matches"
        case pointsToWin   = "points_to_win"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }
}

// MARK: - TournamentStandings

struct TournamentStandings {
    let teamA: TournamentTeam
    let teamB: TournamentTeam
    var pointsTeamA: Double
    var pointsTeamB: Double
    var pointsToWin: Double

    var leader: TournamentTeam? {
        if pointsTeamA > pointsTeamB { return teamA }
        if pointsTeamB > pointsTeamA { return teamB }
        return nil
    }

    var isComplete: Bool {
        pointsTeamA >= pointsToWin || pointsTeamB >= pointsToWin
    }
}

// MARK: - Scoring Functions

/// Match Play: compare best score per hole across each team.
/// Each hole won = 1 pt; hole tied = 0.5 each.
/// Returns overall match points (winner of most holes gets 1 pt, tie = 0.5 each).
func calculateMatchPlayPoints(
    teamARounds: [Round],
    teamBRounds: [Round]
) -> (teamA: Double, teamB: Double) {
    var aHoles = 0.0
    var bHoles = 0.0
    for hole in 0..<18 {
        let a = teamARounds.compactMap { $0.scores[hole] }.min()
        let b = teamBRounds.compactMap { $0.scores[hole] }.min()
        guard let a, let b else { continue }
        if a < b { aHoles += 1 } else if b < a { bHoles += 1 } else { aHoles += 0.5; bHoles += 0.5 }
    }
    if aHoles > bHoles { return (1.0, 0.0) }
    if bHoles > aHoles { return (0.0, 1.0) }
    return (0.5, 0.5)
}

/// Best Ball / Scramble: sum of best score per hole across each team's players.
/// Lower total wins 1 pt; tie = 0.5 each.
func calculateBestBallPoints(
    teamARounds: [Round],
    teamBRounds: [Round]
) -> (teamA: Double, teamB: Double) {
    func bestBallTotal(_ rounds: [Round]) -> Int {
        (0..<18).compactMap { hole in rounds.compactMap { $0.scores[hole] }.min() }.reduce(0, +)
    }
    let a = bestBallTotal(teamARounds)
    let b = bestBallTotal(teamBRounds)
    if a < b { return (1.0, 0.0) }
    if b < a { return (0.0, 1.0) }
    return (0.5, 0.5)
}

/// Stroke Play: lowest total score wins 1 pt; tie = 0.5 each.
func calculateStrokePlayPoints(
    teamARounds: [Round],
    teamBRounds: [Round]
) -> (teamA: Double, teamB: Double) {
    let a = teamARounds.map(\.totalScore).min() ?? Int.max
    let b = teamBRounds.map(\.totalScore).min() ?? Int.max
    if a < b { return (1.0, 0.0) }
    if b < a { return (0.0, 1.0) }
    return (0.5, 0.5)
}

/// Dispatch to the correct scoring function based on match type.
func calculateMatchPoints(
    matchType: TournamentMatchType,
    teamARounds: [Round],
    teamBRounds: [Round]
) -> (teamA: Double, teamB: Double) {
    switch matchType {
    case .matchPlay:            return calculateMatchPlayPoints(teamARounds: teamARounds, teamBRounds: teamBRounds)
    case .bestBall, .scramble:  return calculateBestBallPoints(teamARounds: teamARounds, teamBRounds: teamBRounds)
    case .strokePlay:           return calculateStrokePlayPoints(teamARounds: teamARounds, teamBRounds: teamBRounds)
    }
}

// MARK: - Snake Draft Helper

/// Returns true if Team A (Captain 1) is on the clock for the given pick number.
/// Snake pattern for 2 teams: A, B, B, A, A, B, B, A …
func snakeIsTeamATurn(pickNumber: Int) -> Bool {
    let pos = pickNumber % 4
    return pos == 0 || pos == 3
}
