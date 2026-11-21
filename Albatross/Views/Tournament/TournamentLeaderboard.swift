import SwiftUI

/// The tournament board, set out like a broadcast singles board: a title band, the two teams with
/// their running points, then each day's matches, the leading side of a live match filled in its team colour.
struct TournamentLeaderboard: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The day on screen, by day number. Starts on the day being played.
    @State private var selectedDay: Int?
    /// How tall each day's page is, so the pager can match the day on screen instead of the longest day.
    @State private var pageHeights: [Int: CGFloat] = [:]

    let tournament: Tournament
    /// When set, each match row opens this destination. The Tournaments tab leaves it nil and opens the whole tournament.
    var rowDestination: ((TournamentMatchup) -> AnyView)? = nil

    /// Each team's own colour; a team with none set keeps the default for its side (green and oxblood).
    private var teamAColor: Color { tournament.teamAColor }
    private var teamBColor: Color { tournament.teamBColor }

    /// The paper the bands, score tiles and status column are printed on.
    private let paper = CardAppearance.cream
    private let ink = BookletStyle.pencilGraphite

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var rowHeight: CGFloat { isWide ? 56 : 48 }
    private var statusWidth: CGFloat { isWide ? 88 : 64 }

    var body: some View {
        VStack(spacing: 4) {
            titleBand

            if let standings = tournamentStore.standings(for: tournament) {
                scoreBar(standings)
            }

            if tournament.days.count > 1 {
                dayTabs
            }
            dayPager
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if selectedDay == nil { selectedDay = tournament.currentDay?.number }
        }
    }

    // MARK: - Days

    private var shownDay: Int { selectedDay ?? tournament.currentDay?.number ?? 1 }

    /// Day tabs above the matches. Tapping one moves to it, as swiping does.
    private var dayTabs: some View {
        HStack(spacing: 2) {
            ForEach(tournament.days) { day in
                let isShown = day.number == shownDay
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { selectedDay = day.number }
                } label: {
                    Text("Day \(day.number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isShown ? paper : ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isShown ? ink : paper)
                }
                .buttonStyle(.pressFeedback)
                .accessibilityAddTraits(isShown ? .isSelected : [])
            }
        }
    }

    /// The days side by side: swipe left for the next day, right for the one before.
    private var dayPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(tournament.days) { day in
                    dayPage(day)
                        .containerRelativeFrame(.horizontal)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeights[day.number] = $0 }
                        .id(day.number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $selectedDay)
        .frame(height: pageHeights[shownDay])
        .animation(reduceMotion ? nil : .snappy, value: pageHeights[shownDay])
    }

    private func dayPage(_ day: TournamentDay) -> some View {
        VStack(spacing: 2) {
            dayBand(day)
            ForEach(day.matchups) { matchup in
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bands

    private var titleBand: some View {
        HStack {
            Text(tournament.name)
                .font(isWide ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if let day = tournament.currentDay, tournament.dayCount > 1 {
                Text("Day \(day.number) of \(tournament.dayCount)")
                    .font(.subheadline)
                    .opacity(0.7)
            }
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
        .frame(minHeight: isWide ? 56 : 48)
    }

    private func teamBlock(_ name: String, color: Color, alignment: Alignment) -> some View {
        Text(name)
            .font(isWide ? .title3.weight(.semibold) : .headline)
            .foregroundStyle(color.contrastingText)
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
            .frame(width: isWide ? 88 : 52)
            .frame(maxHeight: .infinity)
            .background(paper)
    }

    /// One day: its number, course and format, and its points once a match has finished.
    private func dayBand(_ day: TournamentDay) -> some View {
        HStack(spacing: 8) {
            Text("Day \(day.number)")
                .font(.subheadline.weight(.semibold))
            Text(dayDetail(day))
                .font(.subheadline)
                .opacity(0.7)
                .lineLimit(1)
            Spacer(minLength: 8)
            if day.matchups.contains(where: { $0.status == .complete }) {
                Text("\(Self.pointsText(day.pointsTeamA)) – \(Self.pointsText(day.pointsTeamB))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(paper)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func dayDetail(_ day: TournamentDay) -> String {
        let course = day.course?.courseName ?? ""
        let format = "\(day.matchType.displayName) \(day.matchType.sideDescription.lowercased())"
        return course.isEmpty ? format : "\(course) · \(format)"
    }

    // MARK: - Match rows

    private func row(_ matchup: TournamentMatchup) -> some View {
        let teamAWon = matchup.status == .complete && matchup.result == .teamAWin
        let teamBWon = matchup.status == .complete && matchup.result == .teamBWin
        let isTie = matchup.status == .complete && matchup.result == .tie
        let live = matchup.status == .active ? tournamentStore.liveStatus[matchup.id] : nil
        let hasLiveScore = (live?.holesPlayed ?? 0) > 0
        let teamALeads = hasLiveScore && (live?.lead ?? 0) > 0
        let teamBLeads = hasLiveScore && (live?.lead ?? 0) < 0
        let allSquare = hasLiveScore && live?.isAllSquare == true

        return HStack(spacing: 2) {
            sideCell(
                names: names(for: matchup.teamAPlayerIDs),
                edgeText: edgeText(won: teamAWon, tie: isTie, points: matchup.pointsTeamA,
                                   leads: teamALeads, square: allSquare, live: live, matchType: matchup.matchType),
                fill: (teamAWon || teamALeads) ? teamAColor : nil,
                isLeading: true)
            statusCell(matchup, live: live)
            sideCell(
                names: names(for: matchup.teamBPlayerIDs),
                edgeText: edgeText(won: teamBWon, tie: isTie, points: matchup.pointsTeamB,
                                   leads: teamBLeads, square: allSquare, live: live, matchType: matchup.matchType),
                fill: (teamBWon || teamBLeads) ? teamBColor : nil,
                isLeading: false)
        }
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: matchup, live: live))
    }

    /// What sits at the outer edge of a side: points once final, the lead while live, "A/S" when level.
    private func edgeText(won: Bool, tie: Bool, points: Double, leads: Bool, square: Bool,
                          live: LiveMatchStatus?, matchType: TournamentMatchType) -> String {
        if won || tie { return Self.pointsText(points) }
        if leads, let live {
            return live.isDormie(matchType: matchType) ? "DORMIE" : Self.leadText(abs(live.lead), matchType: matchType)
        }
        if square { return "A/S" }
        return ""
    }

    /// One side of a match. Names sit next to the status column, the result at the outer edge.
    private func sideCell(names: [BoardName], edgeText: String, fill: Color?, isLeading: Bool) -> some View {
        let nameFont: Font = isWide ? .body.weight(.semibold) : .subheadline.weight(.semibold)
        let nameStack = VStack(alignment: isLeading ? .trailing : .leading, spacing: 0) {
            ForEach(names, id: \.text) { name in
                HStack(spacing: 4) {
                    if name.isCaptain { CaptainBadge(size: 14) }
                    Text(name.text)
                        .font(nameFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        let edge = Text(edgeText)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .frame(minWidth: 16)

        return HStack(spacing: 8) {
            if isLeading {
                edge
                Spacer(minLength: 0)
                nameStack
            } else {
                nameStack
                Spacer(minLength: 0)
                edge
            }
        }
        .foregroundStyle(fill?.contrastingText ?? Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill ?? Color(.secondarySystemGroupedBackground))
    }

    private func statusCell(_ matchup: TournamentMatchup, live: LiveMatchStatus?) -> some View {
        Group {
            switch matchup.status {
            case .complete:
                Text("F")
                    .font(.subheadline.weight(.semibold))
            case .active:
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Circle().fill(teamAColor).frame(width: 6, height: 6)
                        Text("Live").font(.caption.weight(.semibold))
                    }
                    if let live, live.holesPlayed > 0 {
                        Text("Thru \(live.holesPlayed)")
                            .font(.caption2.monospacedDigit())
                            .opacity(0.7)
                    }
                }
            case .pending:
                Text("–")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(ink)
        .frame(width: statusWidth)
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

    /// "2 UP" in match play, strokes ahead ("−2") in the other formats.
    static func leadText(_ lead: Int, matchType: TournamentMatchType) -> String {
        matchType == .matchPlay ? "\(lead) UP" : "−\(lead)"
    }

    private struct BoardName {
        let text: String
        let isCaptain: Bool
    }

    private func names(for playerIDs: [UUID]) -> [BoardName] {
        playerIDs.map { id in
            let profile = tournament.playerPool.first { $0.userID == id }?.profile
            return BoardName(text: Self.boardName(profile?.displayName ?? "Player"),
                             isCaptain: tournament.isCaptain(id))
        }
    }

    private func accessibilityLabel(for matchup: TournamentMatchup, live: LiveMatchStatus?) -> String {
        let sideA = names(for: matchup.teamAPlayerIDs).map(\.text).joined(separator: " and ")
        let sideB = names(for: matchup.teamBPlayerIDs).map(\.text).joined(separator: " and ")
        var label = "Match \(matchup.matchupNumber), \(sideA) against \(sideB)"
        switch matchup.status {
        case .pending: label += ", not started"
        case .active:
            label += ", in progress"
            if let live, live.holesPlayed > 0 {
                label += ", through \(live.holesPlayed)"
                if live.isAllSquare {
                    label += ", all square"
                } else {
                    let leader = live.lead > 0 ? sideA : sideB
                    label += ", \(leader) \(Self.leadText(abs(live.lead), matchType: matchup.matchType).lowercased())"
                if live.isDormie(matchType: matchup.matchType) { label += ", dormie" }
                }
            }
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
