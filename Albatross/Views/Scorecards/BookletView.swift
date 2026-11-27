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

/// How a page moves as the pager scrolls. `value` is -1 when the page has just left to the left, 0 when it is showing,
/// and 1 when it is waiting on the right. Plain numbers, so the scroll transition's closure stays simple.
private nonisolated struct PageTurn {
    let angle: Double
    let offset: CGFloat
    let opacity: Double
    let perspective: CGFloat

    init(isCover: Bool, isFront: Bool, value: Double, width: CGFloat, reduceMotion: Bool) {
        if isCover {
            // The scroll carries the cover off to the left; the offset holds it in place while it turns on its spine.
            let opened = max(0, -value)
            angle = reduceMotion ? 0 : opened * -100
            offset = opened * width
            opacity = reduceMotion ? 1 - opened : (opened < 0.6 ? 1 : max(0, 1 - (opened - 0.6) / 0.4))
            perspective = 0.45
        } else if isFront && value > 0 {
            // Arriving from the right: stay put, under the cover.
            angle = 0
            offset = -value * width
            opacity = 1
            perspective = 0.5
        } else {
            // Reduce Motion keeps the page change but drops the tilt.
            angle = reduceMotion ? 0 : value * -22
            offset = 0
            opacity = 1 - abs(value) * 0.3
            perspective = 0.5
        }
    }
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

    @Environment(RoundStore.self) private var store
    @Environment(CourseStore.self) private var courseStore
    @Environment(CardAppearance.self) private var appearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: BookletPage? = .cover
    @State private var activeHole = 1
    @State private var stripHeight: CGFloat = 0
    @State private var showEditRound = false
    @State private var showCourseDetail = false
    @State private var showCardStyle = false
    @State private var showFinishConfirm = false
    @State private var hasSetUp = false
    /// The scores written this visit, newest last, so a slip can be taken back.
    @State private var scoreHistory: [ScoreEntry] = []
    @State private var lastScoreWrittenAt = Date.distantPast
    @State private var spineEmphasis = false

    private var round: Round? { store.rounds.first { $0.id == roundID } }

    /// One score written to a hole, with what was there before.
    private struct ScoreEntry {
        let hole: Int
        let previous: Int?
    }

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
                Color(uiColor: .systemGroupedBackground)

                BookletPages(
                    round: round,
                    activeHole: $activeHole,
                    page: $page,
                    showCourseDetail: $showCourseDetail,
                    insets: insets,
                    bottomReserve: bottomReserve,
                    isSpread: isSpread,
                    spineEmphasis: spineEmphasis)

                if showsStrip {
                    PencilStrip(
                        hole: activeHole,
                        par: round.effectivePars[activeHole - 1],
                        score: round.scores[activeHole - 1],
                        holesPlayed: round.holesPlayed,
                        tracks: appearance.tracksPuttsAndGreens,
                        putts: round.putts(on: activeHole),
                        greenInRegulation: round.greenInRegulation(on: activeHole),
                        canUndo: !scoreHistory.isEmpty,
                        onScore: { record($0) },
                        onPutts: { recordPutts($0) },
                        onGreen: { recordGreen($0) },
                        onUndo: { undoLastScore() },
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
        // While scoring, the clock and status sit along the top beside the camera and the paper keeps its full width.
        .horizontalToolbarWhereAvailable()
        .sheet(isPresented: $showEditRound) {
            EditRoundSheet(round: round) { _ in }
        }
        .sheet(isPresented: $showCardStyle) {
            NavigationStack {
                ScrollView {
                    CardStyleForm(round: round)
                        .padding(20)
                }
                .navigationTitle("Card Style")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .albatrossConfirm) {
                        Button { showCardStyle = false } label: { Label("Done", systemImage: "checkmark") }
                    }
                }
            }
            .presentationDetents([.large])
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ round: Round) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showEditRound = true } label: {
                    Label("Edit Round", systemImage: "pencil")
                }
                Button { showCardStyle = true } label: {
                    Label("Card Style", systemImage: "paintpalette")
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

    /// Writes a score (or clears it) for the active hole, then moves the pencil on.
    private func record(_ value: Int?) {
        guard var updated = round else { return }
        // A second tap right after the first is a slip, not the next hole's score:
        // the pencil has already moved on, so it would write to the wrong hole.
        if value != nil, Date().timeIntervalSince(lastScoreWrittenAt) < 0.7 { return }
        scoreHistory.append(ScoreEntry(hole: activeHole, previous: updated.scores[activeHole - 1]))
        if scoreHistory.count > 20 { scoreHistory.removeFirst() }
        if value != nil { lastScoreWrittenAt = Date() }
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

    /// Takes back the last score written: that hole gets its old value back and the pencil returns to it.
    private func undoLastScore() {
        guard var updated = round, let entry = scoreHistory.popLast() else { return }
        updated.scores[entry.hole - 1] = entry.previous
        store.update(updated)
        LiveActivityManager.shared.updateActivity(for: updated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastScoreWrittenAt = .distantPast
        activeHole = entry.hole
    }

    /// Putts are written before the score and leave the pencil where it is.
    private func recordPutts(_ value: Int?) {
        guard var updated = round else { return }
        updated.setPutts(value, on: activeHole)
        store.update(updated)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func recordGreen(_ hit: Bool) {
        guard var updated = round else { return }
        updated.setGreen(hit, on: activeHole)
        store.update(updated)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func finishRound() {
        guard var finished = round else { return }
        finished.status = .completed
        store.update(finished)
        LiveActivityManager.shared.endActivity(for: finished)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onShowSummary(roundID, true)
    }

    /// A brief emphasis on the spine when the device opens or closes. Effect only: layout never depends on it.
    private func pulseSpine() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.3)) { spineEmphasis = true }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeIn(duration: 0.4)) { spineEmphasis = false }
        }
    }
}

// MARK: - The pages

/// The cover and the two interior pages: one at a time at compact width, side by side as a spread at
/// regular width. It holds no state of its own, so it is rebuilt only when the round, the active hole
/// or the layout changes, not when the strip or a sheet does.
private struct BookletPages: View {
    let round: Round
    @Binding var activeHole: Int
    @Binding var page: BookletPage?
    @Binding var showCourseDetail: Bool
    let insets: EdgeInsets
    let bottomReserve: CGFloat
    let isSpread: Bool
    let spineEmphasis: Bool

    @Environment(CardAppearance.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The width of one page, so the page transitions can hold a page in place.
    @State private var pageWidth: CGFloat = 400

    var body: some View {
        if isSpread {
            spread
        } else {
            pager
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
    }

    /// One page of the pager, with its turn. The cover is on top and swings open on its spine while the first page waits
    /// underneath, as a booklet opens. The other pages turn as before. Reduce Motion drops the swing for a fade.
    private func pagerPage(_ bookletPage: BookletPage, reduceMotion: Bool, pageWidth: CGFloat) -> some View {
        let isCover = bookletPage == .cover
        let isFront = bookletPage == .front
        let layer: Double = isCover ? 2 : (isFront ? 1 : 0)
        return pageContent(bookletPage)
            .containerRelativeFrame([.horizontal, .vertical])
            .id(bookletPage)
            .zIndex(layer)
            .scrollTransition(axis: .horizontal) { view, phase in
                let turn = PageTurn(isCover: isCover, isFront: isFront, value: phase.value, width: pageWidth, reduceMotion: reduceMotion)
                return view
                    .rotation3DEffect(.degrees(turn.angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: turn.perspective)
                    .offset(x: turn.offset)
                    .opacity(turn.opacity)
            }
    }

    /// One page at a time. Paging gives the flip between cover and interior pages.
    private var pager: some View {
        // The transition closure runs off the main actor, so it gets its own copy of the setting.
        let reduceMotion = self.reduceMotion
        let pageWidth = self.pageWidth
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(BookletPage.allCases) { bookletPage in
                    pagerPage(bookletPage, reduceMotion: reduceMotion, pageWidth: pageWidth)
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
    private func pageContent(_ bookletPage: BookletPage) -> some View {
        switch bookletPage {
        case .cover:
            CourseCoverView(round: round, fillsSpace: true)
                .padding(.top, insets.top + 12)
                .padding(.bottom, insets.bottom + 12)
        case .front:
            paper(holes: 1...9, showsHeader: true)
        case .back:
            paper(holes: 10...18, showsHeader: false)
        }
    }

    /// Both interior pages side by side, like an open booklet.
    private var spread: some View {
        HStack(spacing: 0) {
            paper(holes: 1...9, showsHeader: true)
            Rectangle()
                .fill(Color.black.opacity(spineEmphasis ? 0.35 : 0.14))
                .frame(width: spineEmphasis ? 2 : 1)
            paper(holes: 10...18, showsHeader: false)
        }
    }

    private func paper(holes: ClosedRange<Int>, showsHeader: Bool) -> some View {
        PaperPage(
            // The front names the club; the back says which nine it is.
            title: showsHeader ? round.courseName : "Back nine",
            subtitle: showsHeader ? round.date.formatted(date: .abbreviated, time: .omitted) : backSubtitle,
            holes: holes,
            round: round,
            activeHole: activeHole,
            // The back and options buttons float over the top of a single page. Where the system reports no top inset
            // (the Duo's outer screen), keep the banner clear of them. A spread has no room to spare.
            topInset: isSpread ? insets.top : max(insets.top, 60),
            bottomReserve: bottomReserve,
            opensCourse: showsHeader,
            paper: appearance.pageColor(for: round),
            ink: appearance.ink(for: round),
            tracks: appearance.tracksPuttsAndGreens,
            onCourseTap: { showCourseDetail = true },
            onSelect: { activeHole = $0 }
        )
    }

    /// The back page's line under the banner: where the round stands.
    private var backSubtitle: String {
        guard round.holesPlayed > 0 else { return round.courseName }
        var parts = ["Total \(round.totalScore)"]
        if appearance.tracksPuttsAndGreens {
            if let putts = round.totalPutts { parts.append("\(putts) putts") }
            let greens = round.greens()
            if greens.known > 0 { parts.append("\(greens.hit)/\(greens.known) greens") }
        }
        return parts.joined(separator: " · ")
    }

    private func turnPage(by offset: Int) {
        let current = page?.rawValue ?? 0
        guard let target = BookletPage(rawValue: current + offset) else { return }
        withAnimation { page = target }
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
/// With putts and greens switched on, a second line takes putts and the green before the score,
/// so the score tap that moves the pencil on is always the last one.
/// Press-in feedback for the strip: a small shrink, or a fade when Reduce Motion is on.
private struct StripPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PencilStrip: View {
    let hole: Int
    let par: Int
    let score: Int?
    let holesPlayed: Int
    let tracks: Bool
    let putts: Int?
    let greenInRegulation: Bool?
    let canUndo: Bool
    var onScore: (Int?) -> Void
    var onPutts: (Int?) -> Void
    var onGreen: (Bool) -> Void
    var onUndo: () -> Void
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var buttonHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var chipSize: CGFloat = 44

    private var choices: [(title: String, value: Int)] {
        [("Birdie", par - 1), ("Par", par), ("Bogey", par + 1), ("Double", par + 2), ("Triple", par + 3)]
            .filter { $0.1 >= 1 }
            .map { (title: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hole \(hole)")
                    .appFont(.large, weight: .semibold)
                Text("Par \(par)")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if canUndo {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .appFont(.small, weight: .medium)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(StripPressStyle())
                    .accessibilityHint("Takes back the last score")
                }
                if holesPlayed > 0 {
                    Button(action: onFinish) {
                        Label("Finish \(holesPlayed)/18", systemImage: "flag.checkered")
                            .appFont(.small, weight: .medium)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(StripPressStyle())
                }
            }

            if tracks { greenLine }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { scoreTiles }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) { scoreTiles }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 560)
    }

    /// Putts, then the green: both are optional and neither moves the pencil.
    /// One row when it fits; otherwise the green moves to its own line.
    private var greenLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                puttsRow
                Spacer(minLength: 0)
                greenButton
            }
            VStack(alignment: .leading, spacing: 4) {
                puttsRow
                greenButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var puttsRow: some View {
        HStack(spacing: 4) {
            Text("Putts")
                .appFont(.small)
                .foregroundStyle(.secondary)
                .fixedSize()
            ForEach(0...4, id: \.self) { count in
                Button { onPutts(putts == count ? nil : count) } label: {
                    Text(count == 4 ? "4+" : "\(count)")
                        .appFont(.small, weight: .medium, monospacedDigit: true)
                        .foregroundStyle(putts == count ? (colorScheme == .dark ? Color.black : Color.white) : Color.primary)
                        .frame(width: chipSize - 6, height: chipSize - 12)
                        .background(
                            putts == count ? Color.accentColor : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(width: chipSize, height: chipSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(StripPressStyle())
                .accessibilityLabel("\(count) putts")
                .accessibilityAddTraits(putts == count ? .isSelected : [])
            }
        }
    }

    private var greenButton: some View {
        Button { onGreen(!(greenInRegulation ?? false)) } label: {
            Label("GIR", systemImage: greenInRegulation == true ? "checkmark.circle.fill" : "circle")
                .appFont(.small, weight: .medium)
                .foregroundStyle(greenInRegulation == true ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: chipSize - 12)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minHeight: chipSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(StripPressStyle())
        .accessibilityLabel("Green in regulation")
        .accessibilityValue(greenInRegulation == true ? "Yes" : "No")
    }

    private func scoreButton(title: String, value: Int) -> some View {
        let ink = BookletStyle.ink(forDifference: value - par, onDark: colorScheme == .dark)
        let isCurrent = score == value
        return Button { onScore(value) } label: {
            VStack(spacing: 0) {
                Text(title)
                    .appFont(.small)
                Text("\(value)")
                    .font(.custom(BookletStyle.pencilFontName, size: 28))
            }
            .foregroundStyle(isCurrent ? (colorScheme == .dark ? Color.black : Color.white) : ink)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(isCurrent ? ink : ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(StripPressStyle())
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint("Writes \(value) for hole \(hole)")
    }

    /// Every result relative to par, then More for anything higher.
    @ViewBuilder
    private var scoreTiles: some View {
        ForEach(choices, id: \.title) { choice in
            scoreButton(title: choice.title, value: choice.value)
        }
        moreTile
    }

    /// Any score, and a way to clear the hole. Shows the score itself when it is beyond the tiles.
    private var moreTile: some View {
        let beyondTiles = score.map { value in !choices.contains { $0.value == value } } ?? false
        let ink = BookletStyle.ink(forDifference: (score ?? par + 4) - par, onDark: colorScheme == .dark)
        return Menu {
            ForEach(1...15, id: \.self) { value in
                Button(menuTitle(for: value)) { onScore(value) }
            }
            if score != nil {
                Divider()
                Button(role: .destructive) { onScore(nil) } label: {
                    Label("Clear score", systemImage: "eraser")
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text("More")
                    .appFont(.small)
                if beyondTiles, let score {
                    Text("\(score)")
                        .font(.custom(BookletStyle.pencilFontName, size: 28))
                } else {
                    Image(systemName: "ellipsis")
                        .appFont(.large)
                        .frame(height: 34)
                }
            }
            .foregroundStyle(beyondTiles ? (colorScheme == .dark ? Color.black : Color.white) : Color.primary)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(beyondTiles ? ink : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(StripPressStyle())
        .accessibilityLabel("More scores")
        .accessibilityValue(beyondTiles ? "\(score ?? 0)" : "")
    }

    /// "8 · +4" for a par 4.
    private func menuTitle(for value: Int) -> String {
        let difference = value - par
        let relative = difference == 0 ? "par" : difference > 0 ? "+\(difference)" : "\(difference)"
        return "\(value) · \(relative)"
    }
}

// MARK: - A full-bleed interior page

/// One side of the printed card: a banner, then a ruled table that stretches to the height of the screen.
/// Holes run down the page, or across it when the page is wider than it is tall.
/// The choice follows the measured size, never the device.
private struct PaperPage: View {
    let title: String
    let subtitle: String
    let holes: ClosedRange<Int>
    let round: Round
    let activeHole: Int
    let topInset: CGFloat
    let bottomReserve: CGFloat
    let opensCourse: Bool
    let paper: Color
    let ink: Color
    let tracks: Bool
    var onCourseTap: () -> Void
    var onSelect: (Int) -> Void

    @State private var size: CGSize = .zero

    private var holesAcross: Bool { size.width > size.height * 1.15 }

    var body: some View {
        VStack(spacing: 12) {
            banner
            if holesAcross {
                AcrossTable(round: round, holes: holes, activeHole: activeHole, ink: ink, tracks: tracks, onSelect: onSelect)
            } else {
                DownTable(round: round, holes: holes, activeHole: activeHole, ink: ink, tracks: tracks, onSelect: onSelect)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset + 12)
        .padding(.bottom, bottomReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The paper runs on under the vertical bar at the side of the screen, which floats over it. The table
        // stays where it is, clear of the bar's buttons; only the paper colour reaches the edge.
        .background { paper.ignoresSafeArea(.container, edges: .horizontal) }
        // The paper is always light, so its text and marks read the same in Dark Mode.
        .environment(\.colorScheme, .light)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    /// The printed heading: the club in capitals over a double rule, like the top of a card.
    private var banner: some View {
        let content = VStack(spacing: 4) {
            Text(title)
                .appFont(.small, weight: .semibold)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .appFont(.small)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Rectangle().fill(ink).frame(height: 1.5)
                Rectangle().fill(ink.opacity(0.5)).frame(height: 0.5)
            }
            .padding(.top, 4)
        }
        return Group {
            if opensCourse {
                Button(action: onCourseTap) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows course details")
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card data

private extension Round {
    func yards(_ hole: Int) -> Int? {
        guard let yards = courseYardages, yards.indices.contains(hole - 1), yards[hole - 1] > 0 else { return nil }
        return yards[hole - 1]
    }

    func handicap(_ hole: Int) -> Int? {
        guard let values = courseHandicaps, values.indices.contains(hole - 1), values[hole - 1] > 0 else { return nil }
        return values[hole - 1]
    }

    var hasYards: Bool { (1...18).contains { yards($0) != nil } }
    var hasHandicaps: Bool { (1...18).contains { handicap($0) != nil } }

    func parTotal(_ holes: ClosedRange<Int>) -> Int { holes.reduce(0) { $0 + effectivePars[$1 - 1] } }

    func yardTotal(_ holes: ClosedRange<Int>) -> Int? {
        hasYards ? holes.reduce(0) { $0 + (yards($1) ?? 0) } : nil
    }

    func scoreTotal(_ holes: ClosedRange<Int>) -> Int? {
        let played = holes.compactMap { scores[$0 - 1] }
        return played.isEmpty ? nil : played.reduce(0, +)
    }
}

/// One column of the printed card.
private enum CardColumn {
    case hole, yards, handicap, par, score, putts, green

    var heading: String {
        switch self {
        case .hole:     return "Hole"
        case .yards:    return "Yds"
        case .handicap: return "Hcp"
        case .par:      return "Par"
        case .score:    return "Score"
        case .putts:    return "Putt"
        case .green:    return "GIR"
        }
    }

    /// Width as a share of the table. The score column takes whatever is left.
    var share: CGFloat {
        switch self {
        case .hole:     return 0.13
        case .yards:    return 0.14
        case .handicap: return 0.10
        case .par:      return 0.10
        case .putts:    return 0.12
        case .green:    return 0.10
        case .score:    return 0
        }
    }
}

/// Which columns a card has depends on the course data and on what the player tracks.
/// A manual round gets hole, par and score; putts and greens are added when switched on.
private struct CardLayout {
    let columns: [CardColumn]

    init(round: Round, tracks: Bool) {
        var columns: [CardColumn] = [.hole]
        if round.hasYards { columns.append(.yards) }
        if round.hasHandicaps { columns.append(.handicap) }
        columns.append(.par)
        columns.append(.score)
        if tracks { columns.append(contentsOf: [.putts, .green]) }
        self.columns = columns
    }

    func width(of column: CardColumn, in total: CGFloat) -> CGFloat {
        if column != .score { return total * column.share }
        let used = columns.filter { $0 != .score }.reduce(CGFloat(0)) { $0 + total * $1.share }
        return max(0, total - used)
    }
}

// MARK: - Holes down the page

private struct DownTable: View {
    let round: Round
    let holes: ClosedRange<Int>
    let activeHole: Int
    let ink: Color
    let tracks: Bool
    var onSelect: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var bandHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var totalRowHeight: CGFloat = 36

    private var layout: CardLayout { CardLayout(round: round, tracks: tracks) }
    private var totalRowCount: Int { holes.upperBound == 9 ? 1 : 2 }

    var body: some View {
        // The table is sized from the space the page offers, never from its own content,
        // so it fills the page exactly and cannot overflow it.
        GeometryReader { proxy in
            let total = proxy.size.width
            // Both pages reserve two footer rows, so front and back rows are the same height.
            let rowsHeight = max(0, proxy.size.height - bandHeight - totalRowHeight * 2)
            let rowHeight = max(minimumRowHeight, rowsHeight / CGFloat(holes.count))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(layout.columns, id: \.self) { column in
                        Text(column.heading)
                            .appFont(.small, weight: .semibold)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: layout.width(of: column, in: total))
                    }
                }
                .frame(height: bandHeight)
                .background(ink, ignoresSafeAreaEdges: [])

                // Rows fill the page; at large text sizes they keep a minimum and scroll.
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(holes), id: \.self) { hole in
                            row(hole, total: total)
                                .frame(height: rowHeight)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: rowsHeight)

                totals(total: total)
            }
            .overlay { Rectangle().strokeBorder(ink, lineWidth: 1) }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func cell(_ text: String, width: CGFloat, emphasis: Bool = false) -> some View {
        Text(text)
            .appFont(emphasis ? .large : .body, weight: emphasis ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(emphasis ? ink : .primary)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
    }

    @ViewBuilder
    private func cell(_ column: CardColumn, hole: Int, width: CGFloat, isActive: Bool) -> some View {
        switch column {
        case .hole:     cell("\(hole)", width: width, emphasis: true)
        case .yards:    cell(round.yards(hole).map(String.init) ?? "", width: width)
        case .handicap: cell(round.handicap(hole).map(String.init) ?? "", width: width)
        case .par:      cell("\(round.effectivePars[hole - 1])", width: width)
        case .score:
            GeometryReader { proxy in
                ScoreMark(
                    score: round.scores[hole - 1],
                    par: round.effectivePars[hole - 1],
                    side: min(max(proxy.size.height * 0.78, 24), 56),
                    isActive: isActive,
                    accent: ink
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: width)
        case .putts:
            Text(round.putts(on: hole).map(String.init) ?? "")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                .foregroundStyle(BookletStyle.pencilGraphite)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
        case .green:
            GreenDot(hit: round.greenInRegulation(on: hole), ink: ink)
                .frame(width: width)
                .frame(maxHeight: .infinity)
        }
    }

    private func row(_ hole: Int, total: CGFloat) -> some View {
        let isActive = hole == activeHole
        return Button { onSelect(hole) } label: {
            HStack(spacing: 0) {
                ForEach(layout.columns, id: \.self) { column in
                    cell(column, hole: hole, width: layout.width(of: column, in: total), isActive: isActive)
                }
            }
            .background(isActive ? ink.opacity(0.16) : (hole % 2 == 0 ? ink.opacity(0.05) : Color.clear))
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(hole), par \(round.effectivePars[hole - 1])")
        .accessibilityValue(accessibilityValue(hole))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func accessibilityValue(_ hole: Int) -> String {
        var parts = [round.scores[hole - 1].map { "\($0)" } ?? "No score"]
        if let putts = round.putts(on: hole) { parts.append("\(putts) putts") }
        if round.greenInRegulation(on: hole) == true { parts.append("green in regulation") }
        return parts.joined(separator: ", ")
    }

    /// Out on the front page; In and Total on the back, as printed on a card.
    @ViewBuilder
    private func totals(total: CGFloat) -> some View {
        VStack(spacing: 0) {
            if holes.upperBound == 9 {
                totalRow("Out", holes: holes, total: total)
            } else {
                totalRow("In", holes: holes, total: total)
                totalRow("Total", holes: 1...18, total: total)
            }
        }
        .background(ink.opacity(0.1), ignoresSafeAreaEdges: [])
        .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 1) }
    }

    private func totalRow(_ label: String, holes range: ClosedRange<Int>, total: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(layout.columns, id: \.self) { column in
                footerCell(column, label: label, range: range)
                    .frame(width: layout.width(of: column, in: total))
            }
        }
        .appFont(.body)
        .monospacedDigit()
        .frame(height: totalRowHeight)
    }

    @ViewBuilder
    private func footerCell(_ column: CardColumn, label: String, range: ClosedRange<Int>) -> some View {
        switch column {
        case .hole:
            Text(label)
                .appFont(.small, weight: .semibold)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(ink)
        case .yards:    Text(round.yardTotal(range).map(String.init) ?? "")
        case .handicap: Text("")
        case .par:      Text("\(round.parTotal(range))")
        case .score:
            Text(round.scoreTotal(range).map(String.init) ?? "—")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 22))
                .foregroundStyle(BookletStyle.pencilGraphite)
        case .putts:
            Text(round.puttsTotal(range).map(String.init) ?? "—")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                .foregroundStyle(BookletStyle.pencilGraphite)
        case .green:
            let greens = round.greens(range)
            Text(greens.known > 0 ? "\(greens.hit)" : "—")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                .foregroundStyle(BookletStyle.pencilGraphite)
        }
    }
}

/// A green in regulation, marked the way a player would on paper: a filled dot, or an open one when missed.
private struct GreenDot: View {
    let hit: Bool?
    let ink: Color

    var body: some View {
        Group {
            switch hit {
            case true?:  Circle().fill(ink).frame(width: 10, height: 10)
            case false?: Circle().strokeBorder(ink.opacity(0.45), lineWidth: 1).frame(width: 10, height: 10)
            case nil:    Color.clear.frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Holes across the page

private struct AcrossTable: View {
    let round: Round
    let holes: ClosedRange<Int>
    let activeHole: Int
    let ink: Color
    let tracks: Bool
    var onSelect: (Int) -> Void

    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 32

    private var totalLabel: String { holes.upperBound == 9 ? "Out" : "In" }

    var body: some View {
        VStack(spacing: 0) {
            // Header band: hole numbers
            line(label: "Hole", background: ink, textColor: .white) { hole in
                Text("\(hole)").appFont(.body, weight: .semibold).foregroundStyle(.white)
            } total: {
                Text(totalLabel).appFont(.small, weight: .semibold).textCase(.uppercase).foregroundStyle(.white)
            }

            if round.hasYards {
                line(label: "Yds") { hole in cellText(round.yards(hole).map(String.init) ?? "") }
                    total: { cellText(round.yardTotal(holes).map(String.init) ?? "") }
            }
            if round.hasHandicaps {
                line(label: "Hcp") { hole in cellText(round.handicap(hole).map(String.init) ?? "") }
                    total: { Text("") }
            }
            line(label: "Par") { hole in cellText("\(round.effectivePars[hole - 1])") }
                total: { cellText("\(round.parTotal(holes))") }

            scoreLine

            if tracks {
                line(label: "Putt") { hole in
                    Text(round.putts(on: hole).map(String.init) ?? "")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                } total: {
                    Text(round.puttsTotal(holes).map(String.init) ?? "—")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                }
                line(label: "GIR") { hole in
                    GreenDot(hit: round.greenInRegulation(on: hole), ink: ink)
                } total: {
                    let greens = round.greens(holes)
                    Text(greens.known > 0 ? "\(greens.hit)" : "—")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 18))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                }
            }
        }
        .overlay { Rectangle().strokeBorder(ink, lineWidth: 1) }
    }

    private func cellText(_ text: String) -> some View {
        Text(text).appFont(.body).monospacedDigit().foregroundStyle(.primary)
    }

    /// One printed line: a label cell, then a cell per hole, then the nine's total.
    private func line<Cell: View, Total: View>(
        label: String,
        background: Color = .clear,
        textColor: Color = .secondary,
        @ViewBuilder cell: @escaping (Int) -> Cell,
        @ViewBuilder total: () -> Total
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .appFont(.small, weight: .semibold)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(background == .clear ? ink : textColor)
                .frame(width: labelWidth)
            ForEach(Array(holes), id: \.self) { hole in
                cell(hole)
                    .frame(maxWidth: .infinity)
                    .frame(height: lineHeight)
                    .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
            }
            total()
                .frame(width: labelWidth)
                .frame(height: lineHeight)
                .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
        }
        .background(background, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
    }

    /// The score line takes the height that is left, with a large cell for each hole.
    private var scoreLine: some View {
        HStack(spacing: 0) {
            Text("Score")
                .appFont(.small, weight: .semibold)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(ink)
                .frame(width: labelWidth)
            ForEach(Array(holes), id: \.self) { hole in
                Button { onSelect(hole) } label: {
                    GeometryReader { proxy in
                        ScoreMark(
                            score: round.scores[hole - 1],
                            par: round.effectivePars[hole - 1],
                            side: min(proxy.size.width * 0.85, proxy.size.height * 0.6, 56),
                            isActive: hole == activeHole,
                            accent: ink
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .background(hole == activeHole ? ink.opacity(0.16) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
                .accessibilityLabel("Hole \(hole), par \(round.effectivePars[hole - 1])")
                .accessibilityValue(round.scores[hole - 1].map { "\($0)" } ?? "No score")
                .accessibilityAddTraits(hole == activeHole ? .isSelected : [])
            }
            Text(round.scoreTotal(holes).map(String.init) ?? "—")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 26))
                .foregroundStyle(BookletStyle.pencilGraphite)
                .frame(width: labelWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5) }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
    }
}

// MARK: - A score as it would be written on paper

/// Circle for under par, square for over par, doubled for two or more either way,
/// in ink that reads at a glance: gold, green, graphite, orange, red.
struct ScoreMark: View {
    let score: Int?
    let par: Int
    let side: CGFloat
    let isActive: Bool
    var accent: Color = .accentColor

    var body: some View {
        ZStack {
            if let score {
                let difference = score - par
                let ink = BookletStyle.ink(forDifference: difference)
                marks(for: difference, ink: ink)
                if score == 2 && par == 5 {
                    Image("albatross-mark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.6, height: side * 0.6)
                        .foregroundStyle(ink)
                } else {
                    Text("\(score)")
                        // The size already follows the row, so the digit must not scale a second time.
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: side * 0.56))
                        .foregroundStyle(ink)
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: side * 0.32, weight: .medium))
                    .foregroundStyle(isActive ? accent : Color(uiColor: .tertiaryLabel))
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
    .environment(store)
    .environment(CourseStore())
}

#Preview("Compact, 390 pt") {
    let store = previewStore()
    NavigationStack {
        BookletView(roundID: store.rounds[0].id) { _, _ in }
    }
    .frame(width: 390)
    .environment(\.horizontalSizeClass, .compact)
    .environment(store)
    .environment(CourseStore())
}

#Preview("Regular, 820 pt, dark") {
    let store = previewStore()
    NavigationStack {
        BookletView(roundID: store.rounds[0].id) { _, _ in }
    }
    .frame(width: 820)
    .environment(\.horizontalSizeClass, .regular)
    .preferredColorScheme(.dark)
    .environment(store)
    .environment(CourseStore())
}
#endif
