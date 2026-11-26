import SwiftUI

enum RoundSortOrder: String, CaseIterable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case bestScore = "Best score"
    case worstScore = "Worst score"
}

/// The library: every round is a booklet on a shelf. Tapping one opens it.
struct ScorecardsView: View {
    @Environment(RoundStore.self) private var store

    var pendingRoundID: Binding<UUID?> = .constant(nil)
    var pendingNewRound: Binding<Bool> = .constant(false)

    @State private var path: [RoundDestination] = []
    @State private var showNewRound = false
    @State private var sortOrder: RoundSortOrder = .newest
    @State private var editingRound: Round? = nil
    /// The card lifted in the stack, if any.
    @State private var expandedRoundID: UUID? = nil
    /// "wallet" stacks the rounds like cards in Wallet; "shelves" lays covers out in rows.
    @AppStorage("scorecardLayout") private var layout = "wallet"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var coverNamespace
    /// A cover is a picture of an object, so it keeps its size at every text size.
    /// Its text scales with the cover, and VoiceOver reads the full description.
    private let coverWidth: CGFloat = 170

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
                .tabMenuToolbar()
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
        #if DEBUG
        .onAppear {
            // -demo-expand lifts the second card so its details can be looked at.
            if CommandLine.arguments.contains("-demo-expand"), expandedRoundID == nil {
                expandedRoundID = (inProgress + completed).dropFirst().first?.id
            }
        }
        #endif
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
            if expandedRoundID != nil && layout == "wallet" {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { expandedRoundID = nil }
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            } else if !completed.isEmpty {
                sortMenu
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if expandedRoundID == nil || layout != "wallet" {
                layoutButton
            }
        }
    }

    private var layoutButton: some View {
        Group {
            Button { layout = layout == "wallet" ? "shelves" : "wallet" } label: {
                Label(layout == "wallet" ? "Show as shelves" : "Show as a stack",
                      systemImage: layout == "wallet" ? "books.vertical" : "rectangle.stack")
            }
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
                if inProgress.isEmpty && completed.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }

                if layout == "wallet" {
                    if !inProgress.isEmpty || !completed.isEmpty {
                        WalletStackView(
                            rounds: inProgress + completed,
                            namespace: coverNamespace,
                            expandedID: $expandedRoundID,
                            onOpen: { path.append(.booklet($0.id, opensNextHole: false)) },
                            onEdit: { editingRound = $0 },
                            onDelete: { store.delete($0) })
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                } else {
                    if !inProgress.isEmpty {
                        sectionHeader("In progress")
                        shelf(inProgress)
                    }

                    if !completed.isEmpty {
                        sectionHeader("Previous rounds")
                        shelf(completed)
                    }
                }

                Spacer().frame(height: 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .appFont(.body, weight: .semibold)
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
                    .buttonStyle(.pressFeedback)
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
        .clippedToHorizontalSafeArea()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image("black-browed-albatross")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("No rounds yet")
                    .appFont(.large, weight: .semibold)

                Text("Tap + to start tracking your first round")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showNewRound = true }) {
                Label("Start new round", systemImage: "plus.circle.fill")
                    .appFont(.body)
                    .appButton(fill: Color.brandGreen, foreground: .white, fullWidth: false, cornerRadius: AppSpacing.buttonHeight / 2)
            }
        }
        .padding(32)
    }
}

#Preview {
    ScorecardsView()
        .environment(CourseStore())
        .environment(TournamentStore())
        .environment(AuthStore())
        .environment({
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
