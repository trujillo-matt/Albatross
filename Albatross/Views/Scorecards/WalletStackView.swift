import SwiftUI

/// The rounds as a stack of cards, one over the next, in the manner of Wallet:
/// every card shows its top edge, and the last one shows in full. Tapping a card lifts it to the top,
/// the others drop away, and its details and actions appear beneath it.
struct WalletStackView: View {
    @Environment(CardAppearance.self) private var appearance

    let rounds: [Round]
    let namespace: Namespace.ID
    /// The card that is lifted, if any. Owned by the screen so its toolbar can offer Close.
    @Binding var expandedID: UUID?
    var onOpen: (Round) -> Void
    var onEdit: (Round) -> Void
    var onDelete: (Round) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How much of each card shows above the next one. Grows with the text size.
    @ScaledMetric(relativeTo: .headline) private var peek: CGFloat = 76

    @State private var width: CGFloat = 340
    @State private var panelHeight: CGFloat = 320
    @State private var roundToDelete: Round?

    /// A card is the shape of a bank card.
    private var cardHeight: CGFloat { width / 1.586 }
    private let panelGap: CGFloat = 12

    /// On a wide screen the lifted card opens like a booklet: the card on the left, what is under it on the right.
    private var opensBesideCard: Bool { horizontalSizeClass == .regular }
    private var halfWidth: CGFloat { (width - panelGap) / 2 }
    /// How far each half sits from the centre line.
    private var halfShift: CGFloat { (halfWidth + panelGap) / 2 }
    private var liftedCardHeight: CGFloat { opensBesideCard ? halfWidth / 1.586 : cardHeight }

    private var collapsedHeight: CGFloat { CGFloat(max(rounds.count - 1, 0)) * peek + cardHeight }
    private var expandedHeight: CGFloat {
        opensBesideCard ? max(liftedCardHeight, panelHeight) : cardHeight + panelGap + panelHeight
    }
    private var expandedRound: Round? { rounds.first { $0.id == expandedID } }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(rounds.enumerated(), id: \.element.id) { index, round in
                card(round, index: index)
            }

            if let round = expandedRound {
                DetailsPanel(
                    round: round,
                    onOpen: { onOpen(round) },
                    onEdit: { onEdit(round) },
                    onDelete: { roundToDelete = round })
                .frame(width: opensBesideCard ? halfWidth : nil)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                .offset(x: opensBesideCard ? halfShift : 0, y: opensBesideCard ? 0 : cardHeight + panelGap)
                .transition(.opacity.combined(with: .offset(y: 40)))
                .zIndex(200)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: expandedID == nil ? collapsedHeight : expandedHeight, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 200) }
        .confirmationDialog("Delete this round?", isPresented: Binding(
            get: { roundToDelete != nil }, set: { if !$0 { roundToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete round", role: .destructive) {
                if let round = roundToDelete {
                    withAnimation(motion) { expandedID = nil }
                    onDelete(round)
                }
                roundToDelete = nil
            }
            Button("Cancel", role: .cancel) { roundToDelete = nil }
        } message: {
            Text("This takes the scorecard off your phone and cannot be undone.")
        }
    }

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }

    @ViewBuilder
    private func card(_ round: Round, index: Int) -> some View {
        let isLast = index == rounds.count - 1
        let isExpanded = expandedID == round.id
        let someoneIsExpanded = expandedID != nil

        // Collapsed: each card sits one edge below the last. Expanded: the chosen card goes to the top
        // and the rest drop off the bottom.
        let collapsedY = CGFloat(index) * peek
        let y = someoneIsExpanded ? (isExpanded ? 0 : expandedHeight + 80) : collapsedY

        let besideDetails = isExpanded && opensBesideCard
        WalletCard(round: round, height: besideDetails ? liftedCardHeight : cardHeight, peek: peek)
            .frame(width: besideDetails ? halfWidth : nil)
            .matchedTransitionSource(id: round.id, in: namespace)
            .offset(x: besideDetails ? -halfShift : 0, y: y)
            .opacity(someoneIsExpanded && !isExpanded ? 0 : 1)
            .zIndex(isExpanded ? 100 : Double(index))
            .overlay(alignment: .top) {
                // Only the visible part takes taps, so a tap always lands on the card you see.
                Button {
                    if isExpanded {
                        onOpen(round)
                    } else {
                        withAnimation(motion) { expandedID = round.id }
                    }
                } label: {
                    Color.clear
                        .frame(height: isExpanded ? (besideDetails ? liftedCardHeight : cardHeight) : (isLast ? cardHeight : peek))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressFeedback)
                .offset(y: y)
                .allowsHitTesting(!someoneIsExpanded || isExpanded)
                .accessibilityLabel(WalletCard.accessibilityDescription(for: round))
                .accessibilityHint(isExpanded ? "Opens the scorecard" : "Shows the card with its details")
                .contextMenu {
                    Button { onEdit(round) } label: { Label("Edit Round", systemImage: "pencil") }
                    Button(role: .destructive) { roundToDelete = round } label: { Label("Delete", systemImage: "trash") }
                }
                .zIndex(isExpanded ? 101 : Double(index))
            }
            .animation(motion, value: expandedID)
    }
}

/// What sits under a lifted card: the round in numbers, then what to do with it.
private struct DetailsPanel: View {
    @Environment(CardAppearance.self) private var appearance

    let round: Round
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var front: [Int?] { Array(round.scores.prefix(9)) }
    private var back: [Int?] { Array(round.scores.dropFirst(9)) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                row("Score", value: scoreText)
                Divider()
                row("Front nine", value: nineText(front))
                Divider()
                row("Back nine", value: nineText(back))
                if appearance.tracksPuttsAndGreens, let putts = round.totalPutts {
                    Divider()
                    row("Putts", value: "\(putts)")
                }
                if appearance.tracksPuttsAndGreens, round.greens().known > 0 {
                    Divider()
                    row("Greens", value: "\(round.greens().hit) of \(round.greens().known)")
                }
                Divider()
                row("Played", value: round.date.formatted(date: .long, time: .omitted))
            }

            Button(action: onOpen) {
                Text(round.status == .completed ? "Open scorecard" : "Open scorecard")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.brandGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.pressFeedback)

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .appFont(.small, weight: .medium)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressFeedback)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(uiColor: .systemRed).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .appFont(.small)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .appFont(.body, monospacedDigit: true)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var scoreText: String {
        guard round.holesPlayed > 0 else { return "Not started" }
        let progress = round.status == .completed ? "" : ", through \(round.holesPlayed)"
        return "\(round.totalScore) (\(WalletCard.toParText(round)))\(progress)"
    }

    private func nineText(_ scores: [Int?]) -> String {
        let played = scores.compactMap { $0 }
        return played.isEmpty ? "–" : "\(played.reduce(0, +))" + (played.count < 9 ? " through \(played.count)" : "")
    }
}

/// One round as a card: the course's paper and ink, the course at the top edge, the score in pencil.
private struct WalletCard: View {
    @Environment(CardAppearance.self) private var appearance

    let round: Round
    let height: CGFloat
    let peek: CGFloat

    private var paper: Color { appearance.coverPaper(for: round) }
    private var ink: Color { appearance.ink(for: round) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(paper)
                // The shadow lifts the card off the one beneath it; it belongs to the paper, not the writing.
                .shadow(color: .black.opacity(0.3), radius: 8, y: -3)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ink.opacity(0.4), lineWidth: 1)
                .padding(4)

            // The edge that always shows.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.courseName)
                        .appFont(.large, weight: .semibold)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .appFont(.small)
                        .foregroundStyle(ink.opacity(0.7))
                }
                Spacer(minLength: 8)
                scoreMark
            }
            .padding(.horizontal, 20)
            .frame(height: peek)

            // What shows when the card is on top of the stack.
            VStack {
                Spacer()
                if let logo = CourseLogoCache.image(for: round.courseLogoURL) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: height * 0.55, maxHeight: max(height - peek - 16, 40))
                        // White logo backgrounds disappear into the paper, as printed ink would.
                        .blendMode(.multiply)
                } else {
                    // No course logo: the bird as one flat colour, like the app icon, in the card's own ink.
                    Image("albatross-mark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .foregroundStyle(ink.opacity(0.45))
                }
                Spacer()
            }
            .padding(.top, peek)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// The score as written in pencil, or how far through an unfinished round.
    @ViewBuilder
    private var scoreMark: some View {
        if round.holesPlayed > 0 {
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(round.totalScore)")
                        .font(.custom(BookletStyle.pencilFontName, size: 30))
                    Text(Self.toParText(round))
                        .font(.custom(BookletStyle.pencilFontName, size: 16))
                }
                .foregroundStyle(BookletStyle.pencilGraphite)
                if round.status == .inProgress {
                    Text("thru \(round.holesPlayed)")
                        .font(.custom(BookletStyle.pencilFontName, size: 14))
                        .foregroundStyle(BookletStyle.pencilGraphite.opacity(0.8))
                }
            }
        }
    }

    /// Strokes against the par of the holes played: "+2", "E", "−1".
    static func toParText(_ round: Round) -> String {
        let difference = zip(round.scores, round.effectivePars).reduce(0) { total, hole in
            guard let score = hole.0 else { return total }
            return total + score - hole.1
        }
        return difference == 0 ? "E" : difference > 0 ? "+\(difference)" : "\(difference)"
    }

    static func accessibilityDescription(for round: Round) -> String {
        var parts = [round.courseName, round.date.formatted(date: .long, time: .omitted)]
        if round.holesPlayed > 0 {
            parts.append("\(round.totalScore) strokes, \(toParText(round)) to par")
        }
        parts.append(round.status == .completed ? "completed" : "\(round.holesPlayed) of 18 holes entered")
        return parts.joined(separator: ", ")
    }
}
