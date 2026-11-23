import Foundation

// MARK: - GroupCard

/// One scorecard in a group that a single person is scoring: one per player, or one per side in scramble and
/// alternate shot. Read from the `rounds` table; only the fields the group screens need.
struct GroupCard: Identifiable, Codable {
    var id: UUID
    var ownerID: UUID
    var scores: [Int?]
    var status: String
    var coursePars: [Int]?
    var courseYardages: [Int]?

    var isComplete: Bool { status == "completed" }
    var total: Int { scores.compactMap { $0 }.reduce(0, +) }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID        = "user_id"
        case scores
        case status
        case coursePars     = "course_pars"
        case courseYardages = "course_yardages"
    }
}

// MARK: - Which cards a match has

extension TournamentMatchup {
    /// Scramble and alternate shot play one ball per side, so the group has one card per side.
    var scoresOneCardPerSide: Bool { matchType == .scramble || matchType == .alternateShot }

    /// Who owns each card, in display order (side A first). Matches what `start_group_scoring` creates.
    var groupCardOwnerIDs: [UUID] {
        if scoresOneCardPerSide {
            return [teamAPlayerIDs.first, teamBPlayerIDs.first].compactMap { $0 }
        }
        return teamAPlayerIDs + teamBPlayerIDs
    }
}

// MARK: - Foursomes

extension TournamentMatchup {
    /// The matches played together as a foursome (mirrors `foursome_of` in migration 012). In singles formats a
    /// session's matches are played two at a time, in match order: 1 and 2, 3 and 4. Any other format is one match.
    func foursome(in all: [TournamentMatchup]) -> [TournamentMatchup] {
        guard let sessionID, matchType == .matchPlay || matchType == .strokePlay else { return [self] }
        let inSession = all.filter { $0.sessionID == sessionID }.sorted { $0.matchupNumber < $1.matchupNumber }
        guard let index = inSession.firstIndex(where: { $0.id == id }) else { return [self] }
        let start = index - (index % 2)
        return Array(inSession[start..<min(start + 2, inSession.count)])
    }

    /// Whether a player is in this match.
    func includes(_ userID: UUID) -> Bool {
        teamAPlayerIDs.contains(userID) || teamBPlayerIDs.contains(userID)
    }
}

extension Array where Element == TournamentMatchup {
    /// Card owners across the foursome, in display order.
    var groupCardOwnerIDs: [UUID] { flatMap(\.groupCardOwnerIDs) }
}

// MARK: - Entry flow

enum GroupScoring {
    /// The next empty cell after (hole, card), walking hole by hole and, within a hole, card by card, wrapping to the
    /// start. `scores[card][hole]` is nil for an empty cell. Nil when everything is filled. Same rule as the web app.
    static func nextEmptyCell(scores: [[Int?]], hole: Int, card: Int) -> (hole: Int, card: Int)? {
        let n = scores.count
        guard n > 0 else { return nil }
        let total = 18 * n
        let start = hole * n + card
        for k in 1..<max(total, 2) {
            let idx = (start + k) % total
            let h = idx / n
            let c = idx % n
            if h < scores[c].count, scores[c][h] == nil { return (h, c) }
        }
        return nil
    }

    /// The first empty cell from the very start, used to open the screen where play left off.
    static func firstEmptyCell(scores: [[Int?]]) -> (hole: Int, card: Int)? {
        guard !scores.isEmpty else { return nil }
        for h in 0..<18 {
            for c in 0..<scores.count where h < scores[c].count && scores[c][h] == nil {
                return (h, c)
            }
        }
        return nil
    }
}

extension GroupCard: Equatable {}
