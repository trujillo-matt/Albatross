import SwiftUI

/// Where a tap on the Scorecards screen can lead.
enum RoundDestination: Hashable {
    case booklet(UUID, opensNextHole: Bool)
    case summary(UUID)
}

private enum BookletPage: Int, CaseIterable, Identifiable {
    case cover, front, back
    var id: Int { rawValue }
}

/// A round as a paper scorecard booklet.
/// With a compact width it shows one page at a time (cover, front nine, back nine).
/// With a regular width it opens flat as a two-page spread.
struct BookletView: View {
    let roundID: UUID
    var opensNextHole = false
    /// Called to show the round summary. `replacing` is true when finishing a round,
    /// so Back returns to the library instead of the finished scorecard.
    var onShowSummary: (_ roundID: UUID, _ replacing: Bool) -> Void

    @EnvironmentObject private var store: RoundStore
    @EnvironmentObject private var courseStore: CourseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var page: BookletPage? = .cover
    @State private var selectedHole: Int?
    @State private var showEditRound = false
    @State private var showCourseDetail = false
    @State private var showFinishConfirm = false
    @State private var hasHandledOpeningHole = false
    @State private var spreadViewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var round: Round? { store.rounds.first { $0.id == roundID } }

    var body: some View {
        if let round {
            content(round)
        } else {
            // The round was deleted while this screen was open.
            Color.clear.onAppear { dismiss() }
        }
    }

    // MARK: - Layout

    private func content(_ round: Round) -> some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                spread(round)
            } else {
                pager(round)
            }
            if showsActionBar {
                actionBar(round)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // The course name already heads the page, so the bar stays quiet.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent(round) }
        // An open booklet takes the whole screen; Back returns to the library.
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showEditRound) {
            EditRoundSheet(round: round) { _ in }
        }
        .sheet(isPresented: $showCourseDetail) {
            CourseDetailView(
                round: round,
                course: courseStore.allCourses.first(where: { $0.id == round.courseID })
            )
        }
        .sheet(isPresented: Binding(get: { selectedHole != nil }, set: { if !$0 { selectedHole = nil } })) {
            if let hole = selectedHole {
                ScoreInputView(
                    holeNumber: hole,
                    par: round.effectivePars[hole - 1],
                    score: scoreBinding(for: hole - 1),
                    onConfirm: { scoreWasEntered() }
                )
            }
        }
        .confirmationDialog("Finish Round?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish Round") { finishRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if round.isComplete {
                Text("Your round is complete with a score of \(round.totalScore).")
            } else {
                Text("You've entered scores for \(round.holesPlayed) of 18 holes. You can still finish early.")
            }
        }
        .onAppear { openNextHoleIfRequested(round) }
    }

    /// One page at a time. Paging gives the flip between cover and interior pages.
    private func pager(_ round: Round) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(BookletPage.allCases) { bookletPage in
                    pageContent(bookletPage, round: round)
                        .containerRelativeFrame(.horizontal)
                        .id(bookletPage)
                        .scrollTransition(axis: .horizontal) { view, phase in
                            // Reduce Motion keeps the page change but drops the tilt.
                            view
                                .rotation3DEffect(
                                    .degrees(reduceMotion ? 0 : phase.value * -22),
                                    axis: (x: 0, y: 1, z: 0),
                                    anchor: .leading,
                                    perspective: 0.5
                                )
                                .opacity(1 - abs(phase.value) * 0.3)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .clippedToHorizontalSafeArea()
        .accessibilityAction(named: "Open scorecard") { withAnimation { page = .front } }
        .accessibilityAction(named: "Next page") { turnPage(by: 1) }
        .accessibilityAction(named: "Previous page") { turnPage(by: -1) }
    }

    @ViewBuilder
    private func pageContent(_ bookletPage: BookletPage, round: Round) -> some View {
        switch bookletPage {
        case .cover:
            VStack(spacing: 16) {
                CourseCoverView(round: round)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 32)
                Label("Swipe to open", systemImage: "chevron.left.2")
                    .font(.custom("Baskerville", size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        case .front:
            holePage(title: "Front 9", holes: 1...9, round: round, showsHeader: true)
        case .back:
            holePage(title: "Back 9", holes: 10...18, round: round, showsHeader: false)
        }
    }

    /// Both interior pages side by side, like an open booklet.
    private func spread(_ round: Round) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                RoundHeader(round: round) { showCourseDetail = true }
                    .padding(.horizontal, 20)
                HStack(spacing: 0) {
                    holePage(title: "Front 9", holes: 1...9, round: round, showsHeader: false)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .padding(.vertical, 12)
                    holePage(title: "Back 9", holes: 10...18, round: round, showsHeader: false)
                }
                .background(BookletStyle.page)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            // Centre the open booklet when the screen is taller than the card.
            .frame(minHeight: spreadViewportHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { spreadViewportHeight = $0 }
    }

    private func holePage(title: String, holes: ClosedRange<Int>, round: Round, showsHeader: Bool) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 16) {
                if showsHeader {
                    RoundHeader(round: round) { showCourseDetail = true }
                }
                HoleGridPage(title: title, holes: holes, round: round) { hole in
                    selectedHole = hole
                }
                // As on a printed card: Out ends the front page, In and Total close the back.
                totalsRow(round, onBackPage: holes.upperBound == 18)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(horizontalSizeClass == .regular ? Color.clear : BookletStyle.page)
        .clipShape(RoundedRectangle(cornerRadius: horizontalSizeClass == .regular ? 0 : 16))
        .padding(.horizontal, horizontalSizeClass == .regular ? 0 : 16)
        .padding(.vertical, horizontalSizeClass == .regular ? 0 : 8)
    }

    private func totalsRow(_ round: Round, onBackPage: Bool) -> some View {
        HStack(spacing: 0) {
            if onBackPage {
                total("In", value: round.backNineTotal, played: round.scores.suffix(9).compactMap { $0 }.count)
                Divider().frame(height: 36)
                total("Total", value: round.totalScore, played: round.holesPlayed)
            } else {
                total("Out", value: round.frontNineTotal, played: round.scores.prefix(9).compactMap { $0 }.count)
            }
        }
        .padding(.top, 4)
    }

    private func total(_ label: String, value: Int, played: Int) -> some View {
        VStack(spacing: 2) {
            Text(played > 0 ? "\(value)" : "—")
                .font(.custom(BookletStyle.pencilFontName, size: 24))
                .foregroundStyle(played > 0 ? BookletStyle.pencilGraphite : Color.secondary)
            Text(label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Action bar

    private var showsActionBar: Bool {
        horizontalSizeClass == .regular || page != .cover
    }

    private func actionBar(_ round: Round) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if round.status == .completed {
                    onShowSummary(roundID, false)
                } else {
                    showFinishConfirm = true
                }
            } label: {
                Text(actionTitle(for: round))
                    .font(.custom("Baskerville-Bold", size: 17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(actionBackground(for: round))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(round.status == .inProgress && round.holesPlayed == 0)
            // On a wide screen the button stays a button, not a bar across the paper.
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func actionTitle(for round: Round) -> String {
        if round.status == .completed { return "Round Summary" }
        return round.isComplete ? "Finish Round" : "Finish Round (\(round.holesPlayed)/18)"
    }

    private func actionBackground(for round: Round) -> Color {
        if round.status == .completed || round.holesPlayed > 0 { return .accentColor }
        return Color.accentColor.opacity(0.4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ round: Round) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showEditRound = true } label: {
                    Label("Edit Round", systemImage: "pencil")
                }
                Button { onShowSummary(roundID, false) } label: {
                    Label("Share Round", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    store.delete(round)
                    dismiss()
                } label: {
                    Label("Delete Round", systemImage: "trash")
                }
            } label: {
                Label("Round Options", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func turnPage(by offset: Int) {
        let current = page?.rawValue ?? 0
        guard let target = BookletPage(rawValue: current + offset) else { return }
        withAnimation { page = target }
    }

    private func scoreBinding(for index: Int) -> Binding<Int?> {
        Binding(
            get: { round?.scores[index] ?? nil },
            set: { newValue in
                guard var updated = round else { return }
                updated.scores[index] = newValue
                store.update(updated)
            }
        )
    }

    /// Writing the first score is what starts the Live Activity, not merely opening the booklet.
    private func scoreWasEntered() {
        guard let round else { return }
        LiveActivityManager.shared.updateActivity(for: round)
    }

    private func finishRound() {
        guard var finished = round else { return }
        finished.status = .completed
        store.update(finished)
        LiveActivityManager.shared.endActivity(for: finished)
        onShowSummary(roundID, true)
    }

    private func openNextHoleIfRequested(_ round: Round) {
        guard opensNextHole, !hasHandledOpeningHole else { return }
        hasHandledOpeningHole = true
        let nextIndex = round.scores.firstIndex(where: { $0 == nil }) ?? 0
        page = nextIndex >= 9 ? .back : .front
        // Give the page a moment to appear before the sheet slides over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            selectedHole = nextIndex + 1
        }
    }
}

// MARK: - Header

private struct RoundHeader: View {
    let round: Round
    var onCourseTap: () -> Void

    var body: some View {
        // Side by side when the name fits beside the total, stacked at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                courseButton
                Spacer(minLength: 8)
                totalView(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                courseButton
                totalView(alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
    }

    private var courseButton: some View {
        Button(action: onCourseTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(round.courseName)
                        .font(.custom("Baskerville-Bold", size: 18))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .accessibilityAddTraits(.isHeader)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(round.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.custom("Baskerville", size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func totalView(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(round.holesPlayed > 0 ? "\(round.totalScore)" : "—")
                .font(.custom(BookletStyle.pencilFontName, size: 34))
                .foregroundStyle(round.holesPlayed > 0 ? BookletStyle.pencilGraphite : Color.secondary)
            Text("total")
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - One page of nine holes

/// Nine holes. The holes run across the page when each has room for a cell,
/// and run down the page otherwise. The choice follows the measured width, never the device.
private struct HoleGridPage: View {
    let title: String
    let holes: ClosedRange<Int>
    let round: Round
    var onSelect: (Int) -> Void

    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var minimumCellWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 40

    private var holesAcross: Bool {
        // Before the first measurement assume there is room, so the grid doesn't flash.
        guard width > 0 else { return true }
        return (width - labelWidth) / CGFloat(holes.count) >= minimumCellWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Baskerville-SemiBold", size: 13))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            if holesAcross {
                acrossGrid
            } else {
                downList
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // MARK: Holes across

    private var acrossGrid: some View {
        VStack(spacing: 8) {
            row(label: "Hole") { hole in
                Text("\(hole)")
                    .font(.custom("Baskerville", size: 12))
                    .foregroundStyle(.secondary)
            }
            row(label: "Par") { hole in
                Text("\(round.effectivePars[hole - 1])")
                    .font(.custom("Baskerville", size: 13))
                    .foregroundStyle(.primary)
            }
            Divider()
            row(label: "Score") { hole in
                BookletScoreCell(round: round, hole: hole, height: cellHeight) { onSelect(hole) }
            }
        }
    }

    private func row<Cell: View>(label: String, @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(Array(holes), id: \.self) { hole in
                cell(hole).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Holes down

    private func holeLabel(_ hole: Int) -> some View {
        Text("Hole \(hole)")
            .font(.custom("Baskerville-SemiBold", size: 17))
    }

    private func parLabel(_ hole: Int) -> some View {
        Text("Par \(round.effectivePars[hole - 1])")
            .font(.custom("Baskerville", size: 14))
            .foregroundStyle(.secondary)
    }

    private var downList: some View {
        VStack(spacing: 0) {
            ForEach(Array(holes), id: \.self) { hole in
                HStack(spacing: 12) {
                    // One line when it fits; two lines at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            holeLabel(hole)
                            parLabel(hole)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            holeLabel(hole)
                            parLabel(hole)
                        }
                    }
                    Spacer(minLength: 8)
                    BookletScoreCell(round: round, hole: hole, height: cellHeight) { onSelect(hole) }
                        .frame(maxWidth: 96)
                }
                .padding(.vertical, 2)
                if hole < holes.upperBound { Divider() }
            }
        }
    }
}

// MARK: - A score as it would be written on paper

/// Circle for under par, square for over par, double for two or more either way.
private struct BookletScoreCell: View {
    let round: Round
    let hole: Int
    let height: CGFloat
    var action: () -> Void

    private var score: Int? { round.scores[hole - 1] }
    private var par: Int { round.effectivePars[hole - 1] }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let score {
                    marks(for: score - par)
                    if score == 2 && par == 5 {
                        Image("black-browed-albatross")
                            .resizable()
                            .scaledToFit()
                            .frame(width: height * 0.55, height: height * 0.55)
                    } else {
                        Text("\(score)")
                            // The cell height already scales with Dynamic Type, so the digit must not scale twice.
                            .font(.custom(BookletStyle.pencilFontName, fixedSize: height * 0.5))
                            .foregroundStyle(BookletStyle.pencilGraphite)
                    }
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: height * 0.28, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(hole), par \(par)")
        .accessibilityValue(score.map { "\($0)" } ?? "No score")
    }

    @ViewBuilder
    private func marks(for difference: Int) -> some View {
        let side = height * 0.78
        let line = Color.primary.opacity(0.55)
        switch difference {
        case ...(-2):
            ZStack {
                Circle().strokeBorder(line, lineWidth: 1)
                Circle().strokeBorder(line, lineWidth: 1).padding(3)
            }
            .frame(width: side, height: side)
        case -1:
            Circle().strokeBorder(line, lineWidth: 1.2)
                .frame(width: side, height: side)
        case 0:
            EmptyView()
        case 1:
            Rectangle().strokeBorder(line, lineWidth: 1.2)
                .frame(width: side, height: side)
        default:
            ZStack {
                Rectangle().strokeBorder(line, lineWidth: 1)
                Rectangle().strokeBorder(line, lineWidth: 1).padding(3)
            }
            .frame(width: side, height: side)
        }
    }
}
