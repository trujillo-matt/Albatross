import SwiftUI

/// Paper and pencil used across the booklet: covers, pages and penciled scores.
enum BookletStyle {
    /// Handwriting face for scores written "in pencil".
    static let pencilFontName = "BradleyHandITCTT-Bold"
    static let pencilGraphite = Color(white: 0.24)

    /// Interior page stock. Paper stays cream in Dark Mode, like real paper under a dark screen.
    static let page = Color(red: 0.985, green: 0.975, blue: 0.94)

    /// Ink for a score, from its difference to par. Colours are chosen to read on cream paper.
    /// `onDark` gives lighter versions of the same inks for controls drawn on a dark surface.
    static func ink(forDifference difference: Int?, onDark: Bool = false) -> Color {
        guard let difference else { return onDark ? Color(white: 0.85) : pencilGraphite }
        switch difference {
        case ...(-2): return onDark ? Color(red: 0.95, green: 0.78, blue: 0.30) : Color(red: 0.70, green: 0.48, blue: 0.02)
        case -1:      return onDark ? Color(red: 0.36, green: 0.80, blue: 0.54) : Color(red: 0.04, green: 0.45, blue: 0.24)
        case 0:       return onDark ? Color(white: 0.85) : pencilGraphite
        case 1:       return onDark ? Color(red: 1.00, green: 0.62, blue: 0.30) : Color(red: 0.82, green: 0.38, blue: 0.08)
        default:      return onDark ? Color(red: 1.00, green: 0.45, blue: 0.45) : Color(red: 0.72, green: 0.10, blue: 0.12)
        }
    }
}

/// Loads saved course logos once and keeps them, so scrolling a shelf of covers stays smooth.
enum CourseLogoCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        // The modification date is part of the key so an edited logo replaces the old one.
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(modified)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// How a cover looks. Chosen from the course name so the same course always gets the same cover.
private struct CoverStyle {
    enum Border { case none, rule, doubleRule }

    let paper: Color
    let ink: Color
    let border: Border

    private static let stocks: [(paper: Color, ink: Color)] = [
        (Color(red: 0.96, green: 0.93, blue: 0.84), Color(red: 0.10, green: 0.30, blue: 0.22)),  // cream, forest
        (Color(red: 0.97, green: 0.97, blue: 0.95), Color(red: 0.11, green: 0.17, blue: 0.35)),  // white, navy
        (Color(red: 0.84, green: 0.90, blue: 0.78), Color(red: 0.12, green: 0.25, blue: 0.18)),  // sage, pine
        (Color(red: 0.90, green: 0.83, blue: 0.69), Color(red: 0.35, green: 0.12, blue: 0.12)),  // tan, oxblood
        (Color(red: 0.87, green: 0.90, blue: 0.93), Color(red: 0.15, green: 0.18, blue: 0.25))   // fog, slate
    ]

    init(courseName: String) {
        // A stable hash: `hashValue` changes between launches.
        let seed = courseName.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let index = abs(seed) % Self.stocks.count
        paper = Self.stocks[index].paper
        ink = Self.stocks[index].ink
        switch abs(seed / 7) % 3 {
        case 0:  border = .none
        case 1:  border = .rule
        default: border = .doubleRule
        }
    }
}

/// A booklet cover generated from the round's course logo and name.
/// Finished and in-progress rounds both show the score penciled in at the bottom.
struct CourseCoverView: View {
    let round: Round
    /// When true the cover stretches to fill the space it is given instead of keeping a booklet's proportions.
    var fillsSpace = false

    private var style: CoverStyle { CoverStyle(courseName: round.courseName) }

    private var parThroughPlayedHoles: Int {
        zip(round.scores, round.effectivePars).reduce(0) { $0 + ($1.0 == nil ? 0 : $1.1) }
    }

    private var differenceText: String {
        let difference = round.totalScore - parThroughPlayedHoles
        if difference == 0 { return "E" }
        return difference > 0 ? "+\(difference)" : "\(difference)"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let corner = width * 0.07
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: width * 0.012,
                bottomLeadingRadius: width * 0.012,
                bottomTrailingRadius: corner,
                topTrailingRadius: corner
            )

            ZStack {
                shape.fill(style.paper)
                spine(width: width)
                border(width: width, corner: corner)
                content(width: width)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.16), radius: width * 0.025, x: 0, y: width * 0.015)
        }
        .aspectRatio(fillsSpace ? nil : 0.72, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Pieces

    /// The stapled edge: a thin darker band along the leading side.
    private func spine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(style.ink.opacity(0.12))
                .frame(width: width * 0.035)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func border(width: CGFloat, corner: CGFloat) -> some View {
        let inset = width * 0.07
        switch style.border {
        case .none:
            EmptyView()
        case .rule:
            RoundedRectangle(cornerRadius: corner * 0.5)
                .strokeBorder(style.ink.opacity(0.55), lineWidth: max(0.5, width * 0.004))
                .padding(inset)
        case .doubleRule:
            ZStack {
                RoundedRectangle(cornerRadius: corner * 0.6)
                    .strokeBorder(style.ink.opacity(0.6), lineWidth: max(0.5, width * 0.005))
                    .padding(inset)
                RoundedRectangle(cornerRadius: corner * 0.45)
                    .strokeBorder(style.ink.opacity(0.4), lineWidth: max(0.5, width * 0.003))
                    .padding(inset + width * 0.022)
            }
        }
    }

    private func content(width: CGFloat) -> some View {
        VStack(spacing: width * 0.04) {
            Spacer(minLength: 0)

            logo(width: width)

            Text(round.courseName.uppercased())
                .font(.custom("Baskerville-SemiBold", fixedSize: width * 0.075))
                .tracking(width * 0.006)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .foregroundStyle(style.ink)

            Text(round.date.formatted(date: .abbreviated, time: .omitted))
                .font(.custom("Baskerville", fixedSize: width * 0.065))
                .foregroundStyle(style.ink.opacity(0.75))

            Spacer(minLength: 0)

            pencilScore(width: width)
        }
        .padding(.horizontal, width * 0.12)
        .padding(.vertical, width * 0.12)
        // Keep clear of the stapled edge.
        .padding(.leading, width * 0.03)
    }

    @ViewBuilder
    private func logo(width: CGFloat) -> some View {
        if let image = CourseLogoCache.image(for: round.courseLogoURL) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: width * 0.5, maxHeight: width * 0.4)
                // White logo backgrounds disappear into the paper, as printed ink would.
                .blendMode(.multiply)
        } else {
            Image("black-browed-albatross")
                .resizable()
                .scaledToFit()
                .frame(width: width * 0.3, height: width * 0.3)
                .opacity(0.6)
                .blendMode(.multiply)
        }
    }

    @ViewBuilder
    private func pencilScore(width: CGFloat) -> some View {
        if round.holesPlayed > 0 {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: width * 0.025) {
                    Text("\(round.totalScore)")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: width * 0.21))
                    Text(differenceText)
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: width * 0.085))
                }
                if round.status == .inProgress {
                    Text("thru \(round.holesPlayed)")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: width * 0.07))
                }
            }
            .foregroundStyle(BookletStyle.pencilGraphite)
            .rotationEffect(.degrees(-3))
            .blendMode(.multiply)
        } else {
            // Keeps the cover balanced before any score is written.
            Color.clear.frame(height: width * 0.1)
        }
    }

    private var accessibilityDescription: String {
        var parts = [round.courseName, round.date.formatted(date: .long, time: .omitted)]
        if round.holesPlayed > 0 {
            parts.append("\(round.totalScore) strokes, \(differenceText) to par")
        }
        parts.append(round.status == .completed ? "completed" : "\(round.holesPlayed) of 18 holes entered")
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack {
        CourseCoverView(round: {
            var round = Round(courseName: "Great Waters at Reynolds")
            round.scores = Array(repeating: 5, count: 18)
            round.status = .completed
            return round
        }())
        CourseCoverView(round: {
            var round = Round(courseName: "TPC Scottsdale Champions")
            round.scores = Array(repeating: 4, count: 9) + Array(repeating: nil, count: 9)
            return round
        }())
    }
    .padding()
    .frame(width: 420)
}
