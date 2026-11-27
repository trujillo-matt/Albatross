import Foundation

/// A news item written the way a sports alert reads: a short headline, then a sentence or two of detail.
/// The feed and the phone alert both show this, so they always say the same thing.
struct NewsStory: Equatable {
    let title: String
    let body: String
}

enum NewsStoryWriter {
    /// How long a match standing stays worth quoting. Older items describe a moment, not the score now.
    private static let standingFreshness: TimeInterval = 15 * 60

    static func story(for item: TournamentNewsItem, in tournaments: [Tournament],
                      liveStatus: [UUID: LiveMatchStatus] = [:], now: Date = Date()) -> NewsStory {
        guard let tournament = tournaments.first(where: { $0.id == item.tournamentID }) else {
            return NewsStory(title: item.headline, body: item.headline)
        }
        let matchup = item.matchupID.flatMap { id in tournament.matchups.first { $0.id == id } }
        let player = item.playerUserID.flatMap { id in tournament.playerPool.first { $0.userID == id } }
        let name = player?.profile?.displayName
        let team = tournament.teams.first { $0.id == player?.teamID }
        let hole = item.hole.map(ordinal)
        let versus = matchup.flatMap { opponents(of: item.playerUserID, in: $0, tournament: tournament) }
        let context = matchContext(matchup: matchup, versus: versus)
        let standing = matchup.flatMap { m in
            now.timeIntervalSince(item.createdAt) < standingFreshness
                ? standingSentence(for: m, status: liveStatus[m.id], tournament: tournament) : nil
        }

        func finish(_ sentences: String?...) -> String {
            sentences.compactMap { $0 }.joined(separator: " ")
        }
        let forTeam = team.map { " for \($0.name)" } ?? ""

        switch item.kind {
        case "ace":
            guard let name, let hole else { break }
            return NewsStory(
                title: "\(name) makes a hole in one",
                body: finish("\(name) holed out from the tee on the \(hole) hole\(forTeam)\(context).",
                             "It is the best score a single hole can have.",
                             standing))
        case "eagle":
            guard let name, let hole else { break }
            return NewsStory(
                title: "\(name) eagles the \(hole)",
                body: finish("\(name) made an eagle on the \(hole) hole\(forTeam)\(context), two shots better than par.",
                             standing))
        case "birdie":
            guard let name, let hole else { break }
            return NewsStory(
                title: "\(name) birdies the \(hole)",
                body: finish("\(name) made a birdie on the \(hole) hole\(forTeam)\(context).", standing))
        case "score_change":
            guard let name, let hole else { break }
            let change = scoreChange(in: item.headline)
            let corrected = change.map { ", changing a \($0.old) to a \($0.new)" } ?? ""
            return NewsStory(
                title: "Score corrected for \(name)",
                body: finish("A score on the card for \(name) was changed on the \(hole) hole\(corrected)\(context).",
                             "Any match totals that depended on it have been recalculated.",
                             standing))
        case "match_result":
            if let matchup, let sentence = resultSentence(for: matchup, tournament: tournament) {
                return NewsStory(title: sentence.title, body: sentence.body)
            }
        default:
            break
        }
        // Lead changes and anything else the database wrote: keep its words and add the live standing.
        return NewsStory(title: item.headline, body: finish("\(item.headline).", standing))
    }

    // MARK: - Pieces

    private static func opponents(of userID: UUID?, in matchup: TournamentMatchup, tournament: Tournament) -> String? {
        guard let userID else { return nil }
        let other: [UUID]
        if matchup.teamAPlayerIDs.contains(userID) { other = matchup.teamBPlayerIDs }
        else if matchup.teamBPlayerIDs.contains(userID) { other = matchup.teamAPlayerIDs }
        else { return nil }
        let names = other.compactMap { id in tournament.playerPool.first { $0.userID == id }?.profile?.displayName }
        return names.isEmpty ? nil : names.formatted(.list(type: .and))
    }

    private static func matchContext(matchup: TournamentMatchup?, versus: String?) -> String {
        switch (matchup, versus) {
        case let (m?, v?): return " in match \(m.matchupNumber) against \(v)"
        case let (m?, nil): return " in match \(m.matchupNumber)"
        default: return ""
        }
    }

    private static func standingSentence(for matchup: TournamentMatchup, status: LiveMatchStatus?, tournament: Tournament) -> String? {
        guard let status, status.holesPlayed > 0, matchup.result == nil else { return nil }
        let through = status.holesPlayed == 18 ? "after 18 holes" : "through \(status.holesPlayed)"
        if status.isAllSquare { return "Match \(matchup.matchupNumber) is all square \(through)." }
        let leaderID = status.lead > 0 ? matchup.teamAID : matchup.teamBID
        let leader = tournament.teams.first { $0.id == leaderID }?.name ?? (status.lead > 0 ? "Team A" : "Team B")
        let margin = abs(status.lead)
        if matchup.matchType == .matchPlay {
            return "\(leader) is \(margin) up in match \(matchup.matchupNumber) \(through)."
        }
        return "\(leader) leads match \(matchup.matchupNumber) by \(margin) \(margin == 1 ? "stroke" : "strokes") \(through)."
    }

    private static func resultSentence(for matchup: TournamentMatchup, tournament: Tournament) -> NewsStory? {
        func teamName(_ id: UUID) -> String { tournament.teams.first { $0.id == id }?.name ?? "A team" }
        func names(_ ids: [UUID]) -> String {
            ids.compactMap { id in tournament.playerPool.first { $0.userID == id }?.profile?.displayName }.formatted(.list(type: .and))
        }
        let sideA = names(matchup.teamAPlayerIDs), sideB = names(matchup.teamBPlayerIDs)
        let tail = "worth a point toward the \(tournament.name)."
        switch matchup.result {
        case .teamAWin:
            return NewsStory(title: "\(teamName(matchup.teamAID)) takes match \(matchup.matchupNumber)",
                             body: "\(sideA) beat \(sideB) in match \(matchup.matchupNumber) for \(teamName(matchup.teamAID)), \(tail)")
        case .teamBWin:
            return NewsStory(title: "\(teamName(matchup.teamBID)) takes match \(matchup.matchupNumber)",
                             body: "\(sideB) beat \(sideA) in match \(matchup.matchupNumber) for \(teamName(matchup.teamBID)), \(tail)")
        case .tie:
            return NewsStory(title: "Match \(matchup.matchupNumber) is halved",
                             body: "\(sideA) and \(sideB) finished match \(matchup.matchupNumber) level, so each team takes half a point toward the \(tournament.name).")
        case nil:
            return nil
        }
    }

    /// "Score changed: Ivy Tan, hole 6, 4 to 3" holds the old and new strokes; the table keeps only the sentence.
    private static func scoreChange(in headline: String) -> (old: String, new: String)? {
        guard let match = headline.wholeMatch(of: /.*, (\d+) to (\d+)/) else { return nil }
        return (String(match.1), String(match.2))
    }

    static func ordinal(_ number: Int) -> String {
        let tens = number % 100
        if (11...13).contains(tens) { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }
}
