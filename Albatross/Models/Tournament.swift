import Foundation
import SwiftUI

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
    case alternateShot = "alternate_shot"

    var displayName: String {
        switch self {
        case .scramble:   return "Scramble"
        case .bestBall:   return "Best Ball"
        case .matchPlay:  return "Match Play"
        case .strokePlay: return "Stroke Play"
        case .alternateShot: return "Alternate Shot"
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

/// Where a session is: a lineup is auto-filled, captains call out matchups, then the matches lock.
enum SessionStatus: String, Codable {
    case pending  = "pending"
    case lineup   = "lineup"
    case callouts = "callouts"
    case locked   = "locked"
    case complete = "complete"

    var displayName: String {
        switch self {
        case .pending:  return "Up next"
        case .lineup:   return "Lineup"
        case .callouts: return "Callouts"
        case .locked:   return "Locked in"
        case .complete: return "Complete"
        }
    }
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
    /// "#RRGGBB", set by an admin or the captain. Nil uses the default for the team's side.
    var color: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID  = "tournament_id"
        case name
        case captainUserID = "captain_user_id"
        case color
    }
}

/// When a player tees off in one session. Players with the same time play together. Set by an admin on the website.
struct TournamentTeeTime: Identifiable, Codable, Equatable {
    var sessionID: UUID
    var tournamentID: UUID
    var userID: UUID
    var teeTime: Date

    var id: String { "\(sessionID.uuidString)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case sessionID    = "session_id"
        case tournamentID = "tournament_id"
        case userID       = "user_id"
        case teeTime      = "tee_time"
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
    /// Nil on tournaments created before sessions existed.
    var sessionID: UUID? = nil
    var calledByTeamID: UUID? = nil
    /// Set when the match is locked in by the callouts.
    var calledAt: Date? = nil
    /// The player keeping score for the whole group, or nil when each player scores their own card.
    var scorerUserID: UUID? = nil

    var isLockedIn: Bool { calledAt != nil }

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
        case sessionID      = "session_id"
        case calledByTeamID = "called_by_team_id"
        case calledAt       = "called_at"
        case scorerUserID   = "scorer_user_id"
    }
}

// MARK: - TournamentSession

/// One block of play inside a day (for example the morning scramble). It has one format; its
/// match count comes from the rosters when the tournament starts.
struct TournamentSession: Identifiable, Codable {
    var id: UUID
    var tournamentID: UUID
    var dayNumber: Int
    var sessionNumber: Int
    var label: String?
    var matchType: TournamentMatchType
    var courseName: String?
    var matchCount: Int
    var status: SessionStatus
    var firstCallerTeamID: UUID?
    var turnTeamID: UUID?
    var consecutivePasses: Int

    var title: String { (label?.isEmpty == false ? label! : "Session \(sessionNumber)") }

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID      = "tournament_id"
        case dayNumber         = "day_number"
        case sessionNumber     = "session_number"
        case label
        case matchType         = "match_type"
        case courseName        = "course_name"
        case matchCount        = "match_count"
        case status
        case firstCallerTeamID = "first_caller_team_id"
        case turnTeamID        = "turn_team_id"
        case consecutivePasses = "consecutive_passes"
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

    /// Whether this user captains one of the teams.
    func isCaptain(_ userID: UUID) -> Bool {
        teams.contains { $0.captainUserID == userID }
    }
    var matchups: [TournamentMatchup] = []
    var sessions: [TournamentSession] = []
    var teeTimes: [TournamentTeeTime] = []

    /// Colour of the first (team A) or second (team B) team, with the same defaults as the website.
    var teamAColor: Color { Color(hex: teams.first?.color) ?? .teamDefaultA }
    var teamBColor: Color { Color(hex: teams.dropFirst().first?.color) ?? .teamDefaultB }

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
    case .bestBall, .scramble, .alternateShot: return calculateBestBallPoints(teamARounds: teamARounds, teamBRounds: teamBRounds)
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

// MARK: - Days and matches

extension TournamentMatchType {
    /// Players on each side of one match. Singles formats pit one player against one,
    /// pairs formats two against two, so the format decides how many matches a team makes.
    var playersPerSide: Int {
        switch self {
        case .matchPlay, .strokePlay: return 1
        case .bestBall, .scramble, .alternateShot: return 2
        }
    }

    /// "Singles" or "Pairs", for the board.
    var sideDescription: String { playersPerSide == 1 ? "Singles" : "Pairs" }
}

/// One day of a tournament: a course, a format, and the matches that format makes from the teams.
struct TournamentDay: Identifiable {
    var id: Int { number }
    let number: Int
    let course: TournamentCourse?
    let matchType: TournamentMatchType
    let matchups: [TournamentMatchup]

    var pointsTeamA: Double { matchups.map(\.pointsTeamA).reduce(0, +) }
    var pointsTeamB: Double { matchups.map(\.pointsTeamB).reduce(0, +) }
    var isComplete: Bool { !matchups.isEmpty && matchups.allSatisfy { $0.status == .complete } }
}

extension Tournament {
    /// Players on the larger team, from the players who have joined.
    var playersPerTeam: Int {
        guard teams.count == 2 else { return playerPool.filter { $0.inviteStatus == .accepted }.count / 2 }
        let counts = teams.map { team in playerPool.filter { $0.teamID == team.id && $0.inviteStatus == .accepted }.count }
        return max(counts.max() ?? 0, 1)
    }

    /// Matches one day of this format makes: every player plays once, so 12 against 12 is
    /// twelve singles matches or six pairs matches.
    static func matchCount(playersPerTeam: Int, matchType: TournamentMatchType) -> Int {
        max(1, playersPerTeam / matchType.playersPerSide)
    }

    var sortedCourses: [TournamentCourse] { courses.sorted { $0.roundNumber < $1.roundNumber } }

    /// How many days the tournament runs.
    var dayCount: Int { max(courses.count, 1) }

    /// Matches across every day. Before the tournament starts this comes from the players;
    /// afterwards it is the matches that exist.
    var matchCount: Int {
        if !matchups.isEmpty { return matchups.count }
        let perTeam = playersPerTeam
        if !sessions.isEmpty {
            return sessions.reduce(0) { $0 + Tournament.matchCount(playersPerTeam: perTeam, matchType: $1.matchType) }
        }
        return sortedCourses.reduce(0) { total, course in
            total + Tournament.matchCount(playersPerTeam: perTeam, matchType: course.matchType ?? matchType)
        }
    }

    /// First to more than half of the points on offer: 12 points available means 6.5.
    static func pointsToWin(matchCount: Int) -> Double {
        (Double(matchCount) / 2).rounded(.down) + 0.5
    }

    /// Sessions in play order.
    var sortedSessions: [TournamentSession] {
        sessions.sorted { ($0.dayNumber, $0.sessionNumber) < ($1.dayNumber, $1.sessionNumber) }
    }

    /// True once matches belong to sessions. Older tournaments keep the slicing below.
    var usesSessions: Bool { !sessions.isEmpty && matchups.contains { $0.sessionID != nil } }

    /// The session being played: the first that is not complete.
    var currentSession: TournamentSession? {
        sortedSessions.first { $0.status != .complete } ?? sortedSessions.last
    }

    func matchups(in session: TournamentSession) -> [TournamentMatchup] {
        matchups.filter { $0.sessionID == session.id }.sorted { $0.matchupNumber < $1.matchupNumber }
    }

    /// The matches grouped by day, in play order.
    var days: [TournamentDay] {
        let ordered = matchups.sorted { $0.matchupNumber < $1.matchupNumber }
        guard !ordered.isEmpty else { return [] }
        if usesSessions {
            // A day is every session with that day number; its format is the first session's.
            let numbers = Array(Set(sortedSessions.map(\.dayNumber))).sorted()
            return numbers.map { number in
                let inDay = sortedSessions.filter { $0.dayNumber == number }
                let ids = Set(inDay.map(\.id))
                return TournamentDay(
                    number: number,
                    course: courses.first(where: { $0.roundNumber == number }),
                    matchType: inDay.first?.matchType ?? matchType,
                    matchups: ordered.filter { match in match.sessionID.map { ids.contains($0) } ?? false }
                )
            }
        }
        let plan = sortedCourses
        guard !plan.isEmpty else {
            return [TournamentDay(number: 1, course: nil, matchType: matchType, matchups: ordered)]
        }

        let perTeam = playersPerTeam
        var result: [TournamentDay] = []
        var start = 0
        for (index, course) in plan.enumerated() {
            let type = course.matchType ?? matchType
            let isLast = index == plan.count - 1
            let count = isLast ? ordered.count - start : Tournament.matchCount(playersPerTeam: perTeam, matchType: type)
            let end = min(ordered.count, start + max(count, 0))
            result.append(TournamentDay(number: index + 1, course: course, matchType: type, matchups: Array(ordered[start..<end])))
            start = end
        }
        return result
    }

    /// The day being played: the first that is not finished.
    var currentDay: TournamentDay? {
        let all = days
        return all.first { !$0.isComplete } ?? all.last
    }
}

// MARK: - Live match status

/// Where a match stands while it is being played.
struct LiveMatchStatus: Equatable {
    /// Holes both sides have a score for.
    var holesPlayed: Int
    /// Holes (match play) or strokes (other formats) team A is ahead by. Negative when team B leads.
    var lead: Int

    var isAllSquare: Bool { lead == 0 }

    /// Match play only: one side leads by as many holes as are left, so it cannot lose the match.
    func isDormie(matchType: TournamentMatchType) -> Bool {
        matchType == .matchPlay && lead != 0 && holesPlayed < 18 && abs(lead) == 18 - holesPlayed
    }

    /// The status of a match from the rounds each side has so far.
    static func from(teamARounds: [Round], teamBRounds: [Round], matchType: TournamentMatchType) -> LiveMatchStatus {
        var played = 0
        var holesWonByA = 0
        var holesWonByB = 0
        var strokesA = 0
        var strokesB = 0
        for hole in 0..<18 {
            guard let a = teamARounds.compactMap({ $0.scores.indices.contains(hole) ? $0.scores[hole] : nil }).min(),
                  let b = teamBRounds.compactMap({ $0.scores.indices.contains(hole) ? $0.scores[hole] : nil }).min()
            else { continue }
            played += 1
            strokesA += a
            strokesB += b
            if a < b { holesWonByA += 1 } else if b < a { holesWonByB += 1 }
        }
        switch matchType {
        case .matchPlay:
            return LiveMatchStatus(holesPlayed: played, lead: holesWonByA - holesWonByB)
        case .strokePlay, .bestBall, .scramble, .alternateShot:
            return LiveMatchStatus(holesPlayed: played, lead: strokesB - strokesA)
        }
    }
}

/// One line of tournament news: a birdie, a changed score, a finished match. Written by the database.
struct TournamentNewsItem: Identifiable, Codable, Equatable {
    var id: UUID
    var tournamentID: UUID
    var kind: String
    var headline: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, headline
        case tournamentID = "tournament_id"
        case createdAt    = "created_at"
    }
}

/// Whether a team's captain is on the callouts page right now.
struct CaptainPresence: Codable {
    var teamID: UUID
    var present: Bool

    enum CodingKeys: String, CodingKey {
        case teamID  = "team_id"
        case present
    }
}
