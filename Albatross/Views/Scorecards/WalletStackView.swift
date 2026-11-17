import SwiftUI

/// The rounds as a stack of cards, one over the next, in the manner of Wallet:
/// every card shows its top edge, and the last one shows in full. Tapping a card opens its booklet.
struct WalletStackView: View {
    @EnvironmentObject private var appearance: CardAppearance

    let rounds: [Round]
    let namespace: Namespace.ID
    var onOpen: (Round) -> Void
    var onEdit: (Round) -> Void
    var onDelete: (Round) -> Void

    /// How much of each card shows above the next one. Grows with the text size.
    @ScaledMetric(relativeTo: .headline) private var peek: CGFloat = 76

    @State private var width: CGFloat = 340

    /// A card is the shape of a bank card.
    private var cardHeight: CGFloat { width / 1.586 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rounds.enumerated()), id: \.element.id) { index, round in
                let isLast = index == rounds.count - 1
                WalletCard(round: round, height: cardHeight, peek: peek)
                    .matchedTransitionSource(id: round.id, in: namespace)
                    // Each slot is only as tall as the visible edge; the card draws on down over the slots below,
                    // and the next card, drawn later, covers it.
                    .frame(height: peek, alignment: .top)
                    .overlay(alignment: .top) {
                        // Only the visible part takes taps, so a tap always opens the card you see.
                        Button { onOpen(round) } label: {
                            Color.clear
                                .frame(height: isLast ? cardHeight : peek)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressFeedback)
                        .accessibilityLabel(WalletCard.accessibilityDescription(for: round))
                        .accessibilityHint("Opens the scorecard")
                        .contextMenu {
                            Button { onEdit(round) } label: { Label("Edit Round", systemImage: "pencil") }
                            Button(role: .destructive) { onDelete(round) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .zIndex(Double(index))
            }
            // Room for the last card to show in full.
            Color.clear.frame(height: max(cardHeight - peek, 0))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 200) }
    }
}

/// One round as a card: the course's paper and ink, the course at the top edge, the score in pencil.
private struct WalletCard: View {
    @EnvironmentObject private var appearance: CardAppearance

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
                        .font(.headline)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
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
                Image("black-browed-albatross")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .opacity(0.55)
                    .blendMode(.multiply)
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
