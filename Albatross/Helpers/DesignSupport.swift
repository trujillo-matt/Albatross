import SwiftUI

// MARK: - Text that follows the user's text size

/// A system font at a chosen design size that still scales with Dynamic Type.
/// Use it where a fixed `.font(.system(size:))` would ignore the user's text size.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: ScaledSystemFont.textStyle(for: size))
        self.weight = weight
    }

    /// Scales along the curve of the text style closest in size, so small captions and large numerals each grow in proportion.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<14: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<20: return .body
        case ..<22: return .title3
        case ..<28: return .title2
        case ..<34: return .title
        default:    return .largeTitle
        }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight))
    }
}

// MARK: - Press feedback

/// Press-in feedback for buttons that would otherwise show nothing: a quick fade, with no motion.
struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressFeedbackStyle {
    static var pressFeedback: PressFeedbackStyle { PressFeedbackStyle() }
}

// MARK: - Brand green

extension Color {
    /// The one green of the app: Pantone 342 C, #006747.
    static let brandGreen = Color(red: 0.0 / 255, green: 103.0 / 255, blue: 71.0 / 255)
    /// The same hue lifted for text and controls on dark surfaces, where #006747 would sink.
    static let brandGreenLight = Color(red: 65.0 / 255, green: 200.0 / 255, blue: 162.0 / 255)
}

// MARK: - Icons

/// One of the app's own line icons (crests, flags, clubs), drawn on one grid in one stroke.
/// They take the colour of the surrounding text unless given another.
struct IconView: View {
    let name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("icon-\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Captain badge

/// A yellow C that goes before a captain's name.
struct CaptainBadge: View {
    var size: CGFloat = 16

    var body: some View {
        Text("C")
            .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(Color(red: 0.98, green: 0.80, blue: 0.18), in: Circle())
            .accessibilityLabel("Captain")
    }
}

// MARK: - Team colours

extension Color {
    /// "#RRGGBB" to a colour, or nil when the text is missing or not a colour.
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    /// The same defaults the web app uses for a team with no colour set.
    static let teamDefaultA = Color.brandGreen
    static let teamDefaultB = Color(red: 0x73 / 255, green: 0x1F / 255, blue: 0x24 / 255)

    /// White or near-black, whichever reads better on this colour.
    var contrastingText: Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.4 ? Color(white: 0.07) : .white
    }
}
