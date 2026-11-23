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
    var size: CGFloat = AppSpacing.listIcon

    init(_ name: String, size: CGFloat = AppSpacing.listIcon) {
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

// MARK: - Design standards
//
// The numbers every screen is built from. Sizes are points at the default text size; text still grows with Dynamic Type.

enum AppSpacing {
    /// Between a section's label and its list.
    static let labelToList: CGFloat = 12
    /// Between one section and the next.
    static let section: CGFloat = 28
    /// Inside a list row.
    static let rowVertical: CGFloat = 12
    static let rowHorizontal: CGFloat = 20
    /// Buttons and calls to action.
    static let buttonHeight: CGFloat = 44
    static let buttonHorizontal: CGFloat = 16
    /// Padding around a button's text, either side. The text and its icon touch: this is the only space between them.
    static let buttonTextInset: CGFloat = 4
    /// Icons.
    static let navIcon: CGFloat = 24
    static let listIcon: CGFloat = 28
}

/// The three text sizes: size / line height.
enum AppTextSize {
    case small   // 14 / 18
    case body    // 16 / 20
    case large   // 18 / 22

    var points: CGFloat {
        switch self { case .small: 14; case .body: 16; case .large: 18 }
    }
    var lineHeight: CGFloat {
        switch self { case .small: 18; case .body: 20; case .large: 22 }
    }
    fileprivate var relativeTo: Font.TextStyle {
        switch self { case .small: .subheadline; case .body: .callout; case .large: .headline }
    }
}

private struct AppTextStyle: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let lineHeight: CGFloat
    private let weight: Font.Weight
    private let monospacedDigits: Bool

    init(_ textSize: AppTextSize, weight: Font.Weight, monospacedDigits: Bool) {
        _size = ScaledMetric(wrappedValue: textSize.points, relativeTo: textSize.relativeTo)
        base = textSize.points
        lineHeight = textSize.lineHeight
        self.weight = weight
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight)
        // The system face is about 1.19 times its size tall on its own; the line spacing makes up the rest of the line height.
        content
            .font(monospacedDigits ? font.monospacedDigit() : font)
            .lineSpacing(max(0, lineHeight * (size / base) - size * 1.19))
    }
}

extension View {
    /// Text at one of the three sizes, 14/18, 16/20 or 18/22.
    func appFont(_ size: AppTextSize, weight: Font.Weight = .regular, monospacedDigit: Bool = false) -> some View {
        modifier(AppTextStyle(size, weight: weight, monospacedDigits: monospacedDigit))
    }

    /// A list row's padding: 12 above and below, 20 either side.
    func appListRowPadding() -> some View {
        padding(.vertical, AppSpacing.rowVertical).padding(.horizontal, AppSpacing.rowHorizontal)
    }
}

/// A label whose icon touches its text. The text has 4 points of padding either side; that is the only space between them.
struct TouchingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.icon
            configuration.title.padding(.horizontal, AppSpacing.buttonTextInset)
        }
    }
}

extension View {
    /// A button's face: 44 high, 16 in from the edge, the text wrapped in 4 of its own padding, and no gap between an icon and its text.
    func appButton<Fill: ShapeStyle>(fill: Fill, foreground: Color? = nil, fullWidth: Bool = true, cornerRadius: CGFloat = 12) -> some View {
        self
            .labelStyle(TouchingLabelStyle())
            .padding(.horizontal, AppSpacing.buttonTextInset)
            .padding(.horizontal, AppSpacing.buttonHorizontal)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: AppSpacing.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .foregroundStyle(foreground ?? Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
