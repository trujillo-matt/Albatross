import Combine
import SwiftUI

/// The paper a scorecard is printed on. `club` lets each course keep its own stock on the shelf.
enum PaperStock: String, CaseIterable, Identifiable {
    /// `inherit` only appears when styling one card: it means "use the default from Settings".
    case inherit, club, cream, white, sage, tan, fog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "Default"
        case .club:  return "Club"
        case .cream: return "Cream"
        case .white: return "White"
        case .sage:  return "Sage"
        case .tan:   return "Tan"
        case .fog:   return "Fog"
        }
    }

    /// nil for `club`, which takes its stock from the course.
    var color: Color? {
        switch self {
        case .inherit, .club: return nil
        case .cream: return Color(red: 0.985, green: 0.975, blue: 0.94)
        case .white: return Color(red: 0.99, green: 0.99, blue: 0.98)
        case .sage:  return Color(red: 0.90, green: 0.94, blue: 0.87)
        case .tan:   return Color(red: 0.93, green: 0.88, blue: 0.78)
        case .fog:   return Color(red: 0.90, green: 0.92, blue: 0.95)
        }
    }
}

/// The printed ink: the card's header band, rules and cover lettering, and the accent of the whole app.
/// `club` uses each course's own ink on the cover and card, and leaves the app on its default green.
enum AccentInk: String, CaseIterable, Identifiable {
    /// `inherit` only appears when styling one card: it means "use the default from Settings".
    case inherit, club, fairway, navy, oxblood, plum, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit:  return "Default"
        case .club:     return "Club"
        case .fairway:  return "Fairway"
        case .navy:     return "Navy"
        case .oxblood:  return "Oxblood"
        case .plum:     return "Plum"
        case .graphite: return "Graphite"
        }
    }

    /// A lighter version of the ink for controls on a dark background, where the printed ink would sink.
    var lightTint: Color {
        switch self {
        case .inherit, .club, .fairway: return Color(red: 0.24, green: 0.78, blue: 0.54)
        case .navy:           return Color(red: 0.48, green: 0.61, blue: 0.96)
        case .oxblood:        return Color(red: 0.96, green: 0.52, blue: 0.54)
        case .plum:           return Color(red: 0.79, green: 0.58, blue: 0.89)
        case .graphite:       return Color(red: 0.80, green: 0.82, blue: 0.85)
        }
    }

    /// The ink as a tint that adapts: the printed ink in light mode, a lighter version in dark mode.
    var adaptiveTint: Color {
        let dark = UIColor(lightTint)
        let light = UIColor(color ?? CardAppearance.fairway)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    var color: Color? {
        switch self {
        case .inherit, .club: return nil
        case .fairway:  return CardAppearance.fairway
        case .navy:     return Color(red: 0.11, green: 0.17, blue: 0.35)
        case .oxblood:  return Color(red: 0.45, green: 0.12, blue: 0.14)
        case .plum:     return Color(red: 0.35, green: 0.17, blue: 0.40)
        case .graphite: return Color(red: 0.20, green: 0.22, blue: 0.25)
        }
    }
}

/// How the player's scorecards look. One place decides paper, ink and what the card records,
/// and it is carried across the app: the card, covers, stats and share images.
@MainActor
final class CardAppearance: ObservableObject {
    static let fairway = Color(red: 0.0, green: 0.404, blue: 0.278)
    static let cream = Color(red: 0.985, green: 0.975, blue: 0.94)

    @Published var paper: PaperStock { didSet { defaults.set(paper.rawValue, forKey: Keys.paper) } }
    @Published var accent: AccentInk { didSet { defaults.set(accent.rawValue, forKey: Keys.accent) } }
    @Published var tracksPuttsAndGreens: Bool { didSet { defaults.set(tracksPuttsAndGreens, forKey: Keys.tracks) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let paper = "cardPaper"
        static let accent = "cardAccent"
        static let tracks = "cardTracksPutts"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paper = PaperStock(rawValue: defaults.string(forKey: Keys.paper) ?? "") ?? .club
        accent = AccentInk(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .club
        tracksPuttsAndGreens = defaults.object(forKey: Keys.tracks) as? Bool ?? true
    }

    /// The tint for controls and highlights across the app.
    var tint: Color { accent.adaptiveTint }

    // MARK: Per-card style

    /// The paper one card uses: its own choice, or the default from Settings.
    func paperStock(for round: Round) -> PaperStock {
        guard let raw = round.paper, let own = PaperStock(rawValue: raw), own != .inherit else { return paper }
        return own
    }

    /// The ink one card uses: its own choice, or the default from Settings.
    func accentInk(for round: Round) -> AccentInk {
        guard let raw = round.ink, let own = AccentInk(rawValue: raw), own != .inherit else { return accent }
        return own
    }

    /// Paper for one card's interior pages.
    func pageColor(for round: Round) -> Color { paperStock(for: round).color ?? Self.cream }

    /// Ink for one card and its cover.
    func ink(for round: Round) -> Color { accentInk(for: round).color ?? CoverStyle(courseName: round.courseName).ink }

    /// Paper for one card's cover.
    func coverPaper(for round: Round) -> Color { paperStock(for: round).color ?? CoverStyle(courseName: round.courseName).paper }
}

/// A row of swatches for choosing paper or ink.
struct SwatchPicker<Value: Hashable & Identifiable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let swatch: (Value) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(values) { value in
                        Button { selection = value } label: {
                            VStack(spacing: 4) {
                                swatch(value)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                                    .overlay {
                                        if selection == value {
                                            Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-4)
                                        }
                                    }
                                    .padding(4)
                                Text(label(value))
                                    .font(.caption2)
                                    .foregroundStyle(selection == value ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.pressFeedback)
                        .accessibilityLabel(label(value))
                        .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Paper, ink and what the card records, with a live preview.
/// With a round it styles that one card; without one it sets the default for every card
/// that has not been given its own style.
struct CardStyleForm: View {
    @EnvironmentObject private var appearance: CardAppearance
    @EnvironmentObject private var store: RoundStore

    /// The card being styled. nil edits the default in Settings.
    var round: Round?

    private var current: Round? {
        guard let round else { return nil }
        return store.rounds.first { $0.id == round.id } ?? round
    }

    private var previewRound: Round {
        current ?? {
            var sample = Round(courseName: "Great Waters")
            sample.scores = [5, 4, 3, 5, 4, 6, 4, 3, 5, 4, 4, 5, 3, 4, 5, 4, 3, 4]
            sample.status = .completed
            return sample
        }()
    }

    private var paperValues: [PaperStock] {
        PaperStock.allCases.filter { round != nil || $0 != .inherit }
    }

    private var inkValues: [AccentInk] {
        AccentInk.allCases.filter { round != nil || $0 != .inherit }
    }

    private var paperBinding: Binding<PaperStock> {
        if let current {
            return Binding(
                get: { current.paper.flatMap(PaperStock.init(rawValue:)) ?? .inherit },
                set: { newValue in update { $0.paper = newValue == .inherit ? nil : newValue.rawValue } })
        }
        return $appearance.paper
    }

    private var inkBinding: Binding<AccentInk> {
        if let current {
            return Binding(
                get: { current.ink.flatMap(AccentInk.init(rawValue:)) ?? .inherit },
                set: { newValue in update { $0.ink = newValue == .inherit ? nil : newValue.rawValue } })
        }
        return $appearance.accent
    }

    private func update(_ change: (inout Round) -> Void) {
        guard var updated = current else { return }
        change(&updated)
        store.update(updated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if round != nil {
                Text("This card only. Other cards keep your default style, set in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CourseCoverView(round: previewRound)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            SwatchPicker(
                title: "Paper",
                values: paperValues,
                selection: paperBinding,
                label: { $0.label },
                swatch: { stock in swatch(stock.color, club: [Color(red: 0.96, green: 0.93, blue: 0.84), Color(red: 0.84, green: 0.90, blue: 0.78)], isDefault: stock == .inherit) }
            )

            SwatchPicker(
                title: "Ink and accent",
                values: inkValues,
                selection: inkBinding,
                label: { $0.label },
                swatch: { ink in swatch(ink.color, club: [Color(red: 0.10, green: 0.30, blue: 0.22), Color(red: 0.11, green: 0.17, blue: 0.35)], isDefault: ink == .inherit) }
            )

            if round == nil {
                Toggle(isOn: $appearance.tracksPuttsAndGreens) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Putts and greens")
                            .font(.body)
                        Text("Adds putts and green in regulation to the card and the entry strip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// A solid swatch, a two-tone one for "Club", or a ring for "Default".
    private func swatch(_ color: Color?, club: [Color], isDefault: Bool) -> AnyView {
        if isDefault {
            return AnyView(
                ZStack {
                    Color(.secondarySystemFill)
                    Image(systemName: "arrow.uturn.backward")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                })
        }
        if let color { return AnyView(color) }
        return AnyView(LinearGradient(colors: club, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
