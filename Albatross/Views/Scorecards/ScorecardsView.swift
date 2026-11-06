import SwiftUI

enum RoundSortOrder: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case bestScore = "Best Score"
    case worstScore = "Worst Score"
}

struct ScorecardsView: View {
    @EnvironmentObject private var store: RoundStore

    var pendingRoundID: Binding<UUID?> = .constant(nil)
    var pendingNewRound: Binding<Bool> = .constant(false)

    @State private var showNewRound = false
    @State private var showSortMenu = false
    @State private var sortOrder: RoundSortOrder = .newest
    @State private var activeRound: Round? = nil
    @State private var finishedRound: Round? = nil
    @State private var navigateToScorecard = false
    @State private var navigateToSummary = false
    @State private var editingRound: Round? = nil
    @State private var openNextHoleOnAppear = false

    @Namespace private var cardNamespace

    private var inProgress: [Round] {
        store.rounds.filter { $0.status == .inProgress && $0.tournamentMatchupID == nil }
    }

    private var completed: [Round] {
        let rounds = store.rounds.filter { $0.status == .completed }
        switch sortOrder {
        case .newest:    return rounds.sorted { $0.date > $1.date }
        case .oldest:    return rounds.sorted { $0.date < $1.date }
        case .bestScore: return rounds.sorted { $0.totalScore < $1.totalScore }
        case .worstScore:return rounds.sorted { $0.totalScore > $1.totalScore }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            roundList
        }
        .navigationTitle("Scorecards")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showNewRound) {
            NewRoundSheet { round in
                openNextHoleOnAppear = false
                activeRound = round
                navigateToScorecard = true
            }
        }
        .sheet(item: $editingRound) { round in
            EditRoundSheet(round: round) { updated in _ = updated }
        }
        .navigationDestination(isPresented: $navigateToScorecard) {
            scorecardDestination
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            summaryDestination
        }
        .onChange(of: pendingRoundID.wrappedValue) { _, newValue in handlePendingRound(newValue) }
        .onChange(of: pendingNewRound.wrappedValue) { _, trigger in
            guard trigger else { return }
            pendingNewRound.wrappedValue = false
            showNewRound = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showNewRound = true }) {
                Label("New Round", systemImage: "plus")
            }
        }
        .frequentAction()
        ToolbarItem(placement: .topBarLeading) {
            if !completed.isEmpty { sortMenu }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(RoundSortOrder.allCases, id: \.self) { order in
                Button(action: { sortOrder = order }) {
                    Label(order.rawValue,
                          systemImage: sortOrder == order ? "checkmark" : "")
                }
            }
        } label: {
            Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private var scorecardDestination: some View {
        if let round = activeRound {
            ScorecardView(round: round, onFinish: { finished in
                self.finishedRound = finished
                navigateToScorecard = false
                navigateToSummary = true
            }, openNextHole: openNextHoleOnAppear)
        }
    }

    @ViewBuilder
    private var summaryDestination: some View {
        if let round = finishedRound {
            RoundSummaryView(round: round)
                .navigationTransition(.zoom(sourceID: round.id, in: cardNamespace))
        }
    }

    private func handlePendingRound(_ roundID: UUID?) {
        guard let roundID else { return }
        if let round = store.rounds.first(where: { $0.id == roundID && $0.status == .inProgress }) {
            openNextHoleOnAppear = true
            activeRound = round
            navigateToScorecard = true
        }
        pendingRoundID.wrappedValue = nil
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image("black-browed-albatross")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
            }

            VStack(spacing: 8) {
                Text("No Rounds Yet")
                    .font(.custom("Baskerville-Bold", size: 20))

                Text("Tap + to start tracking your first round")
                    .font(.custom("Baskerville", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showNewRound = true }) {
                Label("Start New Round", systemImage: "plus.circle.fill")
                    .font(.custom("Baskerville", size: 16))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
    }

    // MARK: - Round list

    private var roundList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Tournaments ──────────────────────────────────────────
                TournamentListView()

                // ── No rounds empty state ─────────────────────────────────
                if inProgress.isEmpty && completed.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }

                // ── In Progress (list rows) ──────────────────────────────
                if !inProgress.isEmpty {
                    sectionHeader("In Progress")
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    // Rows size to their content so large Dynamic Type never clips them.
                    VStack(spacing: 0) {
                        ForEach(inProgress) { round in
                            inProgressRow(round)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(round)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            if round.id != inProgress.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }

                // ── Previous Rounds (2-col grid) ─────────────────────────
                if !completed.isEmpty {
                    sectionHeader("Previous Rounds")
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 12)

                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(completed) { round in
                            completedCard(round)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer().frame(height: 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("Baskerville-Bold", size: 18))
            .foregroundStyle(.primary)
    }

    // MARK: - Logo helper

    @ViewBuilder
    private func roundLogoView(_ round: Round, size: CGFloat) -> some View {
        if let url = round.courseLogoURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: "flag.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - In Progress row

    private func inProgressRow(_ round: Round) -> some View {
        Button(action: {
            openNextHoleOnAppear = false
            activeRound = round
            navigateToScorecard = true
        }) {
            HStack(spacing: 14) {
                roundLogoView(round, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(round.courseName)
                        .font(.custom("Baskerville-SemiBold", size: 15))
                        .foregroundStyle(.primary)

                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("Baskerville", size: 12))
                        .foregroundStyle(.secondary)

                    Text("\(round.holesPlayed) of 18 holes entered")
                        .font(.custom("Baskerville", size: 12))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(round.holesPlayed > 0 ? "\(round.totalScore)" : "—")
                        .font(.custom("Baskerville-Bold", size: 20))
                        .foregroundStyle(.primary)
                    Text("score")
                        .font(.custom("Baskerville", size: 10))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Completed card (grid tile)

    private func completedCard(_ round: Round) -> some View {
        let pars = round.effectivePars
        let frontCount = round.scores.prefix(9).compactMap { $0 }.count
        let backCount  = round.scores.suffix(9).compactMap { $0 }.count
        let totalPar   = pars.reduce(0, +)
        let diff       = round.totalScore - totalPar

        return Button(action: {
            finishedRound = round
            navigateToSummary = true
        }) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Passport image ────────────────────────────────────────
                ZStack {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 14
                    )
                    .fill(Color.accentColor.opacity(0.08))

                    if let url = round.courseLogoURL,
                       let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("black-browed-albatross")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .opacity(0.4)
                    }
                }
                .frame(height: 112)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 14
                    )
                )

                // ── Course name + date ────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    Text(round.courseName)
                        .font(.custom("Baskerville-Bold", size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("Baskerville", size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 6)

                // Tournament badge
                if round.tournamentMatchupID != nil {
                    Label("Tournament", systemImage: "trophy.fill")
                        .font(.custom("Baskerville", size: 9))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }

                // ── 18 coloured hole-dots (9 per row) ────────────────────
                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { i in
                            holeDot(score: round.scores[i], par: pars[i])
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(9..<18, id: \.self) { i in
                            holeDot(score: round.scores[i], par: pars[i])
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 10)

                // ── OUT / IN / ±par footer ────────────────────────────────
                HStack(spacing: 0) {
                    cardStat(
                        value: frontCount > 0 ? "\(round.frontNineTotal)" : "—",
                        label: "OUT"
                    )

                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(width: 0.5, height: 26)

                    cardStat(
                        value: backCount > 0 ? "\(round.backNineTotal)" : "—",
                        label: "IN"
                    )

                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(width: 0.5, height: 26)

                    VStack(spacing: 2) {
                        let diffText: String = {
                            guard round.holesPlayed > 0 else { return "—" }
                            if diff == 0 { return "E" }
                            return diff > 0 ? "+\(diff)" : "\(diff)"
                        }()
                        Text(diffText)
                            .font(.custom("Baskerville-Bold", size: 13))
                            .foregroundStyle(cardDiffColor(diff: diff, holesPlayed: round.holesPlayed))
                        Text(round.holesPlayed > 0 ? "\(round.totalScore)" : "—")
                            .font(.custom("Baskerville", size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: round.id, in: cardNamespace)
        .contextMenu {
            Button(action: { editingRound = round }) {
                Label("Edit Round", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.delete(round)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Hole dot

    @ViewBuilder
    private func holeDot(score: Int?, par: Int) -> some View {
        Group {
            if let score {
                let diff = score - par
                Circle()
                    .fill(holeDotColor(diff: diff))
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 11, height: 11)
        .frame(maxWidth: .infinity)
    }

    private func holeDotColor(diff: Int) -> Color {
        switch diff {
        case ..<(-1): return .blue
        case -1:      return Color.accentColor
        case 0:       return Color(.systemGray3)
        case 1:       return Color(red: 0.95, green: 0.35, blue: 0.25)
        default:      return Color(red: 0.80, green: 0.12, blue: 0.12)
        }
    }

    private func cardStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("Baskerville-Bold", size: 13))
                .foregroundStyle(.primary)
            Text(label)
                .font(.custom("Baskerville", size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func cardDiffColor(diff: Int, holesPlayed: Int) -> Color {
        guard holesPlayed > 0 else { return .secondary }
        if diff < 0 { return .blue }
        if diff == 0 { return .primary }
        return Color(red: 0.95, green: 0.35, blue: 0.25)
    }
}

#Preview {
    ScorecardsView()
        .environmentObject({
            let s = RoundStore()
            var r1 = Round(courseName: "Augusta National")
            r1.scores = Array(repeating: 5, count: 18)
            r1.status = .completed
            var r2 = Round(courseName: "Pebble Beach")
            r2.scores = Array(repeating: 4, count: 18)
            r2.status = .completed
            var r3 = Round(courseName: "TPC Sawgrass")
            r3.scores = Array(repeating: 6, count: 9) + Array(repeating: nil, count: 9)
            r3.status = .inProgress
            s.add(r3); s.add(r1); s.add(r2)
            return s
        }())
}
