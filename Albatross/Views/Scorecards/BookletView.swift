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
/// At compact width it shows one full-screen page at a time (cover, front nine, back nine).
/// At regular width it opens flat as a two-page spread.
/// Scores are written with the pencil strip: one tap per hole, relative to par.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: BookletPage? = .cover
    @State private var activeHole = 1
    @State private var stripHeight: CGFloat = 0
    @State private var showEditRound = false
    @State private var showCourseDetail = false
    @State private var showFinishConfirm = false
    @State private var hasSetUp = false
    @State private var spineEmphasis = false

    private var round: Round? { store.rounds.first { $0.id == roundID } }

    var body: some View {
        if let round {
            content(round)
        } else {
            // The round was deleted while this screen was open.
            Color.clear.onAppear { dismiss() }
        }
    }

    private var isSpread: Bool { horizontalSizeClass == .regular }
    private var showsStrip: Bool { isSpread || page != .cover }

    // MARK: - Layout

    private func content(_ round: Round) -> some View {
        // The pages run edge to edge, under the status area and the home indicator.
        // The insets are read from the live layout and handed to each page as padding.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let bottomReserve = showsStrip
                ? stripHeight + max(insets.bottom, 12) + 12
                : insets.bottom + 12

            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)

                Group {
                    if isSpread {
                        spread(round, insets: insets, bottomReserve: bottomReserve)
                    } else {
                        pager(round, insets: insets, bottomReserve: bottomReserve)
                    }
                }

                if showsStrip {
                    PencilStrip(
                        hole: activeHole,
                        par: round.effectivePars[activeHole - 1],
                        score: round.scores[activeHole - 1],
                        holesPlayed: round.holesPlayed,
                        onScore: { record($0) },
                        onFinish: { showFinishConfirm = true }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, max(insets.bottom, 12))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .snappy, value: showsStrip)
        }
        .ignoresSafeArea(.container, edges: .vertical)
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
        .onAppear { setUp(round) }
        .onChange(of: activeHole) { _, hole in
            // Keep the page that holds the active hole in view.
            guard !isSpread, page != .cover else { return }
            let target: BookletPage = hole > 9 ? .back : .front
            if page != target {
                withAnimation(reduceMotion ? nil : .easeInOut) { page = target }
            }
        }
        .hingeFeedback { pulseSpine() }
    }

    /// One page at a time. Paging gives the flip between cover and interior pages.
    private func pager(_ round: Round, insets: EdgeInsets, bottomReserve: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(BookletPage.allCases) { bookletPage in
                    pageContent(bookletPage, round: round, insets: insets, bottomReserve: bottomReserve)
                        .containerRelativeFrame([.horizontal, .vertical])
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
    private func pageContent(_ bookletPage: BookletPage, round: Round, insets: EdgeInsets, bottomReserve: CGFloat) -> some View {
        switch bookletPage {
        case .cover:
            CourseCoverView(round: round, fillsSpace: true)
                .padding(.horizontal, 12)
                .padding(.top, insets.top + 12)
                // Room under the cover for the hint.
                .padding(.bottom, insets.bottom + 56)
                .overlay(alignment: .bottom) {
                    Label("Swipe to open", systemImage: "chevron.left.2")
                        .font(.custom("Baskerville", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, insets.bottom + 18)
                }
        case .front:
            paper(title: "Front 9", holes: 1...9, round: round, insets: insets, bottomReserve: bottomReserve, showsHeader: true)
        case .back:
            paper(title: "Back 9", holes: 10...18, round: round, insets: insets, bottomReserve: bottomReserve, showsHeader: false)
        }
    }

    /// Both interior pages side by side, like an open booklet.
    private func spread(_ round: Round, insets: EdgeInsets, bottomReserve: CGFloat) -> some View {
        HStack(spacing: 0) {
            paper(title: "Front 9", holes: 1...9, round: round, insets: insets, bottomReserve: bottomReserve, showsHeader: true)
            Rectangle()
                .fill(Color.black.opacity(spineEmphasis ? 0.35 : 0.14))
                .frame(width: spineEmphasis ? 2 : 1)
            paper(title: "Back 9", holes: 10...18, round: round, insets: insets, bottomReserve: bottomReserve, showsHeader: false)
        }
        .clippedToHorizontalSafeArea()
    }

    private func paper(title: String, holes: ClosedRange<Int>, round: Round, insets: EdgeInsets, bottomReserve: CGFloat, showsHeader: Bool) -> some View {
        PaperPage(
            title: title,
            holes: holes,
            round: round,
            activeHole: activeHole,
            topInset: insets.top,
            bottomReserve: bottomReserve,
            showsHeader: showsHeader,
            onCourseTap: { showCourseDetail = true },
            onSelect: { activeHole = $0 }
        )
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
                if round.status == .inProgress {
                    Button { showFinishConfirm = true } label: {
                        Label("Finish Round", systemImage: "flag.checkered")
                    }
                    .disabled(round.holesPlayed == 0)
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

    private func setUp(_ round: Round) {
        guard !hasSetUp else { return }
        hasSetUp = true
        // The pencil starts on the next empty hole.
        let nextIndex = round.scores.firstIndex(where: { $0 == nil }) ?? 0
        activeHole = nextIndex + 1
        if opensNextHole {
            page = nextIndex >= 9 ? .back : .front
        }
    }

    private func turnPage(by offset: Int) {
        let current = page?.rawValue ?? 0
        guard let target = BookletPage(rawValue: current + offset) else { return }
        withAnimation { page = target }
    }

    /// Writes a score (or clears it) for the active hole, then moves the pencil on.
    private func record(_ value: Int?) {
        guard var updated = round else { return }
        updated.scores[activeHole - 1] = value
        store.update(updated)
        // Writing a score is what starts the Live Activity, not merely opening the booklet.
        LiveActivityManager.shared.updateActivity(for: updated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard value != nil else { return }
        for offset in 1...18 {
            let index = (activeHole - 1 + offset) % 18
            if updated.scores[index] == nil {
                activeHole = index + 1
                break
            }
        }
    }

    private func finishRound() {
        guard var finished = round else { return }
        finished.status = .completed
        store.update(finished)
        LiveActivityManager.shared.endActivity(for: finished)
        onShowSummary(roundID, true)
    }

    /// A brief emphasis on the spine when the device opens or closes. Effect only: layout never depends on it.
    private func pulseSpine() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.3)) { spineEmphasis = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.4)) { spineEmphasis = false }
        }
    }
}

// MARK: - Fold feedback

private extension View {
    /// Runs `effect` and taps the haptic engine when the device's hinge status changes.
    /// Only iOS 27.1 reports hinge changes; earlier systems simply skip the effect.
    @ViewBuilder
    func hingeFeedback(_ effect: @escaping () -> Void) -> some View {
        if #available(iOS 27.1, *) {
            self.onHingeChange { oldContext, newContext in
                guard oldContext.hinge?.status != newContext.hinge?.status else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                effect()
            }
        } else {
            self
        }
    }
}

// MARK: - The pencil strip

/// The way scores are written: the active hole's par and one button per result, relative to par.
private struct PencilStrip: View {
    let hole: Int
    let par: Int
    let score: Int?
    let holesPlayed: Int
    var onScore: (Int?) -> Void
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var buttonHeight: CGFloat = 52

    private var choices: [(title: String, value: Int)] {
        [("Birdie", par - 1), ("Par", par), ("Bogey", par + 1), ("Double", par + 2)]
            .filter { $0.1 >= 1 }
            .map { (title: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hole \(hole)")
                    .font(.custom("Baskerville-SemiBold", size: 20))
                Text("Par \(par)")
                    .font(.custom("Baskerville", size: 16))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                moreMenu
                if holesPlayed > 0 {
                    Button(action: onFinish) {
                        Label("Finish \(holesPlayed)/18", systemImage: "flag.checkered")
                            .font(.custom("Baskerville-SemiBold", size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(choices, id: \.title) { choice in
                    scoreButton(title: choice.title, value: choice.value)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 560)
    }

    private func scoreButton(title: String, value: Int) -> some View {
        let ink = BookletStyle.ink(forDifference: value - par, onDark: colorScheme == .dark)
        let isCurrent = score == value
        return Button { onScore(value) } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.custom("Baskerville", size: 13))
                Text("\(value)")
                    .font(.custom(BookletStyle.pencilFontName, size: 28))
            }
            .foregroundStyle(isCurrent ? (colorScheme == .dark ? Color.black : Color.white) : ink)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(isCurrent ? ink : ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint("Writes \(value) for hole \(hole)")
    }

    private var moreMenu: some View {
        Menu {
            ForEach(1...12, id: \.self) { value in
                Button("\(value)") { onScore(value) }
            }
            if score != nil {
                Divider()
                Button(role: .destructive) { onScore(nil) } label: {
                    Label("Clear Score", systemImage: "eraser")
                }
            }
        } label: {
            Label("Other score", systemImage: "number")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 32)
        }
        .tint(.primary)
    }
}

// MARK: - A full-bleed interior page

/// Nine holes on cream paper. The rows stretch to the height of the screen.
/// Holes run down the page, or across it when the page is wider than it is tall.
/// The choice follows the measured size, never the device.
private struct PaperPage: View {
    let title: String
    let holes: ClosedRange<Int>
    let round: Round
    let activeHole: Int
    let topInset: CGFloat
    let bottomReserve: CGFloat
    let showsHeader: Bool
    var onCourseTap: () -> Void
    var onSelect: (Int) -> Void

    @State private var size: CGSize = .zero
    @State private var viewportHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 52

    private var holesAcross: Bool { size.width > size.height * 1.15 }

    var body: some View {
        VStack(spacing: 12) {
            if showsHeader {
                RoundHeader(round: round, onCourseTap: onCourseTap)
            }
            titleRow
            if holesAcross {
                acrossGrid
            } else {
                downRows
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 12)
        .padding(.bottom, bottomReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BookletStyle.page)
        // The paper is always light, so its text and marks read the same in Dark Mode.
        .environment(\.colorScheme, .light)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.custom("Baskerville-SemiBold", size: 14))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Group {
                if holes.upperBound == 9 {
                    subtotal("Out", round.frontNineTotal, played: round.scores.prefix(9).compactMap { $0 }.count)
                } else {
                    subtotal("In", round.backNineTotal, played: round.scores.suffix(9).compactMap { $0 }.count)
                    subtotal("Total", round.totalScore, played: round.holesPlayed)
                }
            }
        }
    }

    private func subtotal(_ label: String, _ value: Int, played: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
            Text(played > 0 ? "\(value)" : "—")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 22))
                .foregroundStyle(BookletStyle.pencilGraphite)
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Holes down

    /// Nine equal rows share the measured height, so the page fills the screen.
    /// When text is large the rows keep a readable minimum and the page scrolls.
    private var rowHeight: CGFloat {
        max(minimumRowHeight, (viewportHeight - 8) / CGFloat(holes.count))
    }

    private var downRows: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(holes), id: \.self) { hole in
                    HoleRow(round: round, hole: hole, isActive: hole == activeHole) { onSelect(hole) }
                        .frame(height: rowHeight)
                    if hole < holes.upperBound { Divider() }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    }

    // MARK: Holes across

    private var acrossGrid: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Hole").frame(height: 24)
                Text("Par").frame(height: 24)
                Text("Score").frame(maxHeight: .infinity)
            }
            .font(.custom("Baskerville", size: 12))
            .foregroundStyle(.secondary)
            .frame(width: labelWidth, alignment: .leading)

            ForEach(Array(holes), id: \.self) { hole in
                HoleColumn(round: round, hole: hole, isActive: hole == activeHole) { onSelect(hole) }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Rows and columns

private func holeDetail(_ round: Round, hole: Int) -> String {
    let index = hole - 1
    var parts = ["Par \(round.effectivePars[index])"]
    if let yards = round.courseYardages, yards.indices.contains(index), yards[index] > 0 {
        parts.append("\(yards[index]) yd")
    }
    if let handicaps = round.courseHandicaps, handicaps.indices.contains(index), handicaps[index] > 0 {
        parts.append("Hcp \(handicaps[index])")
    }
    return parts.joined(separator: " · ")
}

private struct HoleRow: View {
    let round: Round
    let hole: Int
    let isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                let side = min(max(proxy.size.height * 0.78, 28), 64)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hole \(hole)")
                            .font(.custom("Baskerville-SemiBold", size: 18))
                            .foregroundStyle(.primary)
                        Text(holeDetail(round, hole: hole))
                            .font(.custom("Baskerville", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    ScoreMark(score: round.scores[hole - 1], par: round.effectivePars[hole - 1], side: side, isActive: isActive)
                }
                .padding(.horizontal, 10)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(hole), par \(round.effectivePars[hole - 1])")
        .accessibilityValue(round.scores[hole - 1].map { "\($0)" } ?? "No score")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct HoleColumn: View {
    let round: Round
    let hole: Int
    let isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text("\(hole)")
                    .font(.custom("Baskerville", size: 13))
                    .foregroundStyle(.secondary)
                    .frame(height: 24)
                Text("\(round.effectivePars[hole - 1])")
                    .font(.custom("Baskerville", size: 14))
                    .foregroundStyle(.primary)
                    .frame(height: 24)
                GeometryReader { proxy in
                    ScoreMark(
                        score: round.scores[hole - 1],
                        par: round.effectivePars[hole - 1],
                        side: min(proxy.size.width * 0.9, proxy.size.height * 0.9, 64),
                        isActive: isActive
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(hole), par \(round.effectivePars[hole - 1])")
        .accessibilityValue(round.scores[hole - 1].map { "\($0)" } ?? "No score")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - A score as it would be written on paper

/// Circle for under par, square for over par, doubled for two or more either way,
/// in ink that reads at a glance: gold, green, graphite, orange, red.
private struct ScoreMark: View {
    let score: Int?
    let par: Int
    let side: CGFloat
    let isActive: Bool

    var body: some View {
        ZStack {
            if let score {
                let difference = score - par
                let ink = BookletStyle.ink(forDifference: difference)
                marks(for: difference, ink: ink)
                if score == 2 && par == 5 {
                    Image("black-browed-albatross")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.6, height: side * 0.6)
                } else {
                    Text("\(score)")
                        // The size already follows the row, so the digit must not scale a second time.
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: side * 0.56))
                        .foregroundStyle(ink)
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: side * 0.32, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color(.tertiaryLabel))
            }
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func marks(for difference: Int, ink: Color) -> some View {
        switch difference {
        case ...(-2):
            ZStack {
                Circle().strokeBorder(ink, lineWidth: 1.4)
                Circle().strokeBorder(ink, lineWidth: 1.4).padding(4)
            }
        case -1:
            Circle().strokeBorder(ink, lineWidth: 1.6)
        case 0:
            EmptyView()
        case 1:
            Rectangle().strokeBorder(ink, lineWidth: 1.6)
        default:
            ZStack {
                Rectangle().strokeBorder(ink, lineWidth: 1.4)
                Rectangle().strokeBorder(ink, lineWidth: 1.4).padding(4)
            }
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
    }

    private var courseButton: some View {
        Button(action: onCourseTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(round.courseName)
                        .font(.custom("Baskerville-SemiBold", size: 20))
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

// MARK: - Previews

#if DEBUG
private func previewStore() -> RoundStore {
    let store = RoundStore()
    var round = Round(courseName: "Great Waters at Reynolds")
    round.scores = [5, 6, 5, 4, 6, 5, 6, 3, 7, 6, 5, 4, 7, 4, 5, 4, 3, 5]
    store.add(round)
    return store
}

/// The same booklet at a very narrow, a compact and a regular width.
/// Size classes come from the environment, not from the frame, so they are set explicitly.
#Preview("Narrow, 280 pt") {
    let store = previewStore()
    NavigationStack {
        BookletView(roundID: store.rounds[0].id) { _, _ in }
    }
    .frame(width: 280)
    .environment(\.horizontalSizeClass, .compact)
    .environmentObject(store)
    .environmentObject(CourseStore())
}

#Preview("Compact, 390 pt") {
    let store = previewStore()
    NavigationStack {
        BookletView(roundID: store.rounds[0].id) { _, _ in }
    }
    .frame(width: 390)
    .environment(\.horizontalSizeClass, .compact)
    .environmentObject(store)
    .environmentObject(CourseStore())
}

#Preview("Regular, 820 pt, dark") {
    let store = previewStore()
    NavigationStack {
        BookletView(roundID: store.rounds[0].id) { _, _ in }
    }
    .frame(width: 820)
    .environment(\.horizontalSizeClass, .regular)
    .preferredColorScheme(.dark)
    .environmentObject(store)
    .environmentObject(CourseStore())
}
#endif
