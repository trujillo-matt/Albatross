import Combine
import SwiftUI

/// The paper a scorecard is printed on. `club` lets each course keep its own stock on the shelf.
enum PaperStock: String, CaseIterable, Identifiable {
    case club, cream, white, sage, tan, fog

    var id: String { rawValue }

    var label: String {
        switch self {
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
        case .club:  return nil
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
    case club, fairway, navy, oxblood, plum, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
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
        case .club, .fairway: return Color(red: 0.24, green: 0.78, blue: 0.54)
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
        case .club:     return nil
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

    /// Paper for the interior pages.
    var pageColor: Color { paper.color ?? Self.cream }

    /// Ink for one course's card and cover.
    func ink(for courseName: String) -> Color { accent.color ?? CoverStyle(courseName: courseName).ink }

    /// Paper for one course's cover.
    func coverPaper(for courseName: String) -> Color { paper.color ?? CoverStyle(courseName: courseName).paper }
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
                        .buttonStyle(.plain)
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

/// Paper, ink and what the card records, with a live preview. Used from Settings and from a booklet.
struct CardStyleForm: View {
    @EnvironmentObject private var appearance: CardAppearance

    /// Shown in the preview. Falls back to a sample card when nil.
    var sample: Round?

    private var previewRound: Round {
        sample ?? {
            var round = Round(courseName: "Great Waters")
            round.scores = [5, 4, 3, 5, 4, 6, 4, 3, 5, 4, 4, 5, 3, 4, 5, 4, 3, 4]
            round.status = .completed
            return round
        }()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CourseCoverView(round: previewRound)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            SwatchPicker(
                title: "Paper",
                values: PaperStock.allCases,
                selection: $appearance.paper,
                label: { $0.label },
                swatch: { stock in
                    if let color = stock.color {
                        AnyView(color)
                    } else {
                        AnyView(LinearGradient(
                            colors: [Color(red: 0.96, green: 0.93, blue: 0.84), Color(red: 0.84, green: 0.90, blue: 0.78)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            )

            SwatchPicker(
                title: "Ink and accent",
                values: AccentInk.allCases,
                selection: $appearance.accent,
                label: { $0.label },
                swatch: { ink in
                    if let color = ink.color {
                        AnyView(color)
                    } else {
                        AnyView(LinearGradient(
                            colors: [Color(red: 0.10, green: 0.30, blue: 0.22), Color(red: 0.11, green: 0.17, blue: 0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            )

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
