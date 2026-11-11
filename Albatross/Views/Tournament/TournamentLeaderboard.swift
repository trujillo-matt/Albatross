import SwiftUI

/// The tournament board, set out like a broadcast singles board: a title band, the two teams with
/// their points, then one row per match with the winner's side filled in its team colour.
struct TournamentLeaderboard: View {
    @EnvironmentObject private var tournamentStore: TournamentStore

    let tournament: Tournament
    /// When set, each match row opens this destination. The Tournaments tab leaves it nil and opens the whole tournament.
    var rowDestination: ((TournamentMatchup) -> AnyView)? = nil

    /// Team A takes the app's green; team B takes the oxblood ink from the scorecards.
    private let teamAColor = Color.brandGreen
    private let teamBColor = Color(red: 0.45, green: 0.12, blue: 0.14)

    /// The paper the title band, score tiles and status column are printed on.
    private let paper = CardAppearance.cream
    private let ink = BookletStyle.pencilGraphite

    private var matchups: [TournamentMatchup] {
        tournament.matchups.sorted { $0.matchupNumber < $1.matchupNumber }
    }

    var body: some View {
        VStack(spacing: 4) {
            titleBand

            if let standings = tournamentStore.standings(for: tournament) {
                scoreBar(standings)
            }

            VStack(spacing: 2) {
                ForEach(matchups) { matchup in
                    if let rowDestination {
                        NavigationLink(destination: rowDestination(matchup)) {
                            row(matchup)
                        }
                        .buttonStyle(.pressFeedback)
                    } else {
                        row(matchup)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Title and score bars

    private var titleBand: some View {
        HStack {
            Text(tournament.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(tournament.matchType.displayName)
                .font(.subheadline)
                .opacity(0.7)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(paper)
    }

    private func scoreBar(_ standings: TournamentStandings) -> some View {
        HStack(spacing: 2) {
            teamBlock(standings.teamA.name, color: teamAColor, alignment: .leading)
            pointsTile(standings.pointsTeamA)
            pointsTile(standings.pointsTeamB)
            teamBlock(standings.teamB.name, color: teamBColor, alignment: .trailing)
        }
        .frame(minHeight: 48)
    }

    private func teamBlock(_ name: String, color: Color, alignment: Alignment) -> some View {
        Text(name)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(color)
    }

    private func pointsTile(_ points: Double) -> some View {
        Text(Self.pointsText(points))
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(ink)
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .background(paper)
    }

    // MARK: - Match rows

    private func row(_ matchup: TournamentMatchup) -> some View {
        let teamAWon = matchup.status == .complete && matchup.result == .teamAWin
        let teamBWon = matchup.status == .complete && matchup.result == .teamBWin
        let isTie = matchup.status == .complete && matchup.result == .tie

        return HStack(spacing: 2) {
            sideCell(
                names: names(for: matchup.teamAPlayerIDs),
                points: matchup.pointsTeamA,
                showsPoints: teamAWon || isTie,
                fill: teamAWon ? teamAColor : nil,
                isLeading: true)
            statusCell(matchup)
            sideCell(
                names: names(for: matchup.teamBPlayerIDs),
                points: matchup.pointsTeamB,
                showsPoints: teamBWon || isTie,
                fill: teamBWon ? teamBColor : nil,
                isLeading: false)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: matchup))
    }

    /// One side of a match. Names sit next to the status column, the result at the outer edge.
    private func sideCell(names: [String], points: Double, showsPoints: Bool, fill: Color?, isLeading: Bool) -> some View {
        let nameStack = VStack(alignment: isLeading ? .trailing : .leading, spacing: 0) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        let result = Text(showsPoints ? Self.pointsText(points) : "")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .frame(minWidth: 16)

        return HStack(spacing: 8) {
            if isLeading {
                result
                Spacer(minLength: 0)
                nameStack
            } else {
                nameStack
                Spacer(minLength: 0)
                result
            }
        }
        .foregroundStyle(fill == nil ? Color.primary : Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill ?? Color(.secondarySystemGroupedBackground))
    }

    private func statusCell(_ matchup: TournamentMatchup) -> some View {
        Group {
            switch matchup.status {
            case .complete:
                Text("F")
            case .active:
                HStack(spacing: 4) {
                    Circle().fill(teamAColor).frame(width: 6, height: 6)
                    Text("Live").font(.caption.weight(.semibold))
                }
            case .pending:
                Text("–")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ink)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(paper)
    }

    // MARK: - Helpers

    /// "M TRUJILLO" from "Matt Trujillo": first initial and surname, as on a broadcast board.
    static func boardName(_ displayName: String) -> String {
        let parts = displayName.split(separator: " ")
        guard let first = parts.first else { return "—" }
        guard parts.count > 1, let last = parts.last, let initial = first.first else {
            return String(first).uppercased()
        }
        return "\(initial) \(last)".uppercased()
    }

    /// 1 → "1", 0.5 → "½", 1.5 → "1½".
    static func pointsText(_ points: Double) -> String {
        let whole = Int(points)
        let hasHalf = points - Double(whole) >= 0.5
        if hasHalf { return whole == 0 ? "½" : "\(whole)½" }
        return "\(whole)"
    }

    private func names(for playerIDs: [UUID]) -> [String] {
        playerIDs.map { id in
            let profile = tournament.playerPool.first { $0.userID == id }?.profile
            return Self.boardName(profile?.displayName ?? "Player")
        }
    }

    private func accessibilityLabel(for matchup: TournamentMatchup) -> String {
        let sideA = names(for: matchup.teamAPlayerIDs).joined(separator: " and ")
        let sideB = names(for: matchup.teamBPlayerIDs).joined(separator: " and ")
        var label = "Match \(matchup.matchupNumber), \(sideA) against \(sideB)"
        switch matchup.status {
        case .pending: label += ", not started"
        case .active: label += ", in progress"
        case .complete:
            switch matchup.result {
            case .teamAWin: label += ", final, \(sideA) won"
            case .teamBWin: label += ", final, \(sideB) won"
            default: label += ", final, halved"
            }
        }
        return label
    }
}
