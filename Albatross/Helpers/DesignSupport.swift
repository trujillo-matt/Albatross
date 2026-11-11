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
