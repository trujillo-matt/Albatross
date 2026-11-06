import SwiftUI

enum RoundSortOrder: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case bestScore = "Best Score"
    case worstScore = "Worst Score"
}

/// The library: every round is a booklet on a shelf. Tapping one opens it.
struct ScorecardsView: View {
    @EnvironmentObject private var store: RoundStore

    var pendingRoundID: Binding<UUID?> = .constant(nil)
    var pendingNewRound: Binding<Bool> = .constant(false)

    @State private var path: [RoundDestination] = []
    @State private var showNewRound = false
    @State private var sortOrder: RoundSortOrder = .newest
    @State private var editingRound: Round? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var coverNamespace
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 170

    private var inProgress: [Round] {
        store.rounds.filter { $0.status == .inProgress && $0.tournamentMatchupID == nil }
    }

    private var completed: [Round] {
        let rounds = store.rounds.filter { $0.status == .completed }
        switch sortOrder {
        case .newest:     return rounds.sorted { $0.date > $1.date }
        case .oldest:     return rounds.sorted { $0.date < $1.date }
        case .bestScore:  return rounds.sorted { $0.totalScore < $1.totalScore }
        case .worstScore: return rounds.sorted { $0.totalScore > $1.totalScore }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            library
                .navigationTitle("Scorecards")
                .toolbar { toolbarContent }
                .navigationDestination(for: RoundDestination.self) { destination in
                    destinationView(destination)
                }
        }
        .sheet(isPresented: $showNewRound) {
            NewRoundSheet { round in
                path.append(.booklet(round.id, opensNextHole: false))
            }
        }
        .sheet(item: $editingRound) { round in
            EditRoundSheet(round: round) { _ in }
        }
        .onChange(of: pendingRoundID.wrappedValue) { _, newValue in handlePendingRound(newValue) }
        .onChange(of: pendingNewRound.wrappedValue) { _, trigger in
            guard trigger else { return }
            pendingNewRound.wrappedValue = false
            // Start from the library so the sheet doesn't compete with an open booklet.
            path.removeAll()
            showNewRound = true
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destinationView(_ destination: RoundDestination) -> some View {
        switch destination {
        case .booklet(let roundID, let opensNextHole):
            BookletView(roundID: roundID, opensNextHole: opensNextHole) { id, replacing in
                showSummary(for: id, replacingBooklet: replacing)
            }
            .navigationTransition(.zoom(sourceID: roundID, in: coverNamespace))
        case .summary(let roundID):
            if let round = store.rounds.first(where: { $0.id == roundID }) {
                RoundSummaryView(round: round)
            }
        }
    }

    private func showSummary(for roundID: UUID, replacingBooklet: Bool) {
        if replacingBooklet, !path.isEmpty {
            path.removeLast()
        }
        path.append(.summary(roundID))
    }

    private func handlePendingRound(_ roundID: UUID?) {
        guard let roundID else { return }
        if store.rounds.contains(where: { $0.id == roundID && $0.status == .inProgress }) {
            path = [.booklet(roundID, opensNextHole: true)]
        }
        pendingRoundID.wrappedValue = nil
    }

    // MARK: - Toolbar

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

    // MARK: - Library

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TournamentListView()

                if inProgress.isEmpty && completed.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }

                if !inProgress.isEmpty {
                    sectionHeader("In Progress")
                    shelf(inProgress)
                }

                if !completed.isEmpty {
                    sectionHeader("Previous Rounds")
                    shelf(completed)
                }

                Spacer().frame(height: 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("Baskerville-Bold", size: 18))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)
    }

    /// A row of covers that scrolls sideways and settles on one at a time.
    private func shelf(_ rounds: [Round]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: 16) {
                ForEach(rounds) { round in
                    NavigationLink(value: RoundDestination.booklet(round.id, opensNextHole: false)) {
                        CourseCoverView(round: round)
                            .frame(width: coverWidth)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: round.id, in: coverNamespace)
                    .scrollTransition(axis: .horizontal) { view, phase in
                        view
                            .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.95)
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : phase.value * 10),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.6
                            )
                    }
                    .contextMenu {
                        Button { editingRound = round } label: {
                            Label("Edit Round", systemImage: "pencil")
                        }
                        Button(role: .destructive) { store.delete(round) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
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
}

#Preview {
    ScorecardsView()
        .environmentObject(CourseStore())
        .environmentObject(TournamentStore())
        .environmentObject(AuthStore())
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
