import SwiftUI

// Shared brand color used in rendered share cards
// (Color.accentColor doesn't resolve in ImageRenderer, so we use the explicit value)
private let brandGreen = Color(red: 0.141, green: 0.208, blue: 0.153)

// MARK: - Logo loader helper

/// Loads the course logo UIImage from disk synchronously.
/// Called before ImageRenderer so the image is ready at render time.
func loadCourseLogo(for round: Round) -> UIImage? {
    guard let url = round.courseLogoURL,
          let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}

// MARK: - Template 1: Minimal / Clean

struct MinimalShareCard: View {
    let round: Round
    var logoImage: UIImage? = nil

    var body: some View {
        ZStack {
            Color.white

            VStack(spacing: 0) {
                // Top accent bar
                Rectangle()
                    .fill(brandGreen)
                    .frame(height: 6)

                Spacer()

                VStack(spacing: 28) {
                    // Course logo or app brand mark
                    if let logo = logoImage {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    } else {
                        HStack(spacing: 6) {
                            Image("black-browed-albatross")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Albatross")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }

                    // Score
                    VStack(spacing: 8) {
                        Text("\(round.totalScore)")
                            .font(.system(size: 96, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text("strokes")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color(.secondaryLabel))
                    }

                    // Course & date
                    VStack(spacing: 6) {
                        Text(round.courseName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)

                        Text(round.date.formatted(date: .long, time: .omitted))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                Spacer()

                // Bottom row
                HStack {
                    miniStat(label: "Front", value: round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—")
                    Spacer()
                    miniStat(label: "Holes", value: "\(round.holesPlayed)/18")
                    Spacer()
                    miniStat(label: "Back", value: round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

// MARK: - Template 2: Bold / Dark

struct BoldShareCard: View {
    let round: Round
    var logoImage: UIImage? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.08),
                    Color(red: 0.141, green: 0.208, blue: 0.153)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.white.opacity(0.03))

            VStack(spacing: 0) {
                // Top branding
                HStack {
                    HStack(spacing: 8) {
                        if let logo = logoImage {
                            Image(uiImage: logo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        } else {
                            Image("black-browed-albatross")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .colorMultiply(.white)
                        }
                        Text("ALBATROSS")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)

                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCORE")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(4)
                            .foregroundStyle(.white.opacity(0.6))

                        Text("\(round.totalScore)")
                            .font(.system(size: 100, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(round.courseName.uppercased())
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Text(round.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer()

                HStack(spacing: 0) {
                    boldStat(label: "FRONT", value: round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—")
                    boldStat(label: "BACK", value: round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
                    boldStat(label: "HOLES", value: "\(round.holesPlayed)/18")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(.white.opacity(0.07))
            }
        }
    }

    private func boldStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Template 3: Scorecard style

struct ScorecardShareCard: View {
    let round: Round
    var logoImage: UIImage? = nil

    private var pars: [Int] { round.effectivePars }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.95) // Aged paper tint

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    if let logo = logoImage {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Image("black-browed-albatross")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }

                    VStack(alignment: logoImage != nil ? .leading : .center, spacing: 2) {
                        Text(round.courseName)
                            .font(.system(size: 18, weight: .semibold))
                            .multilineTextAlignment(logoImage != nil ? .leading : .center)
                        Text(round.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    if logoImage != nil { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: logoImage != nil ? .leading : .center)
                .padding(.horizontal, logoImage != nil ? 16 : 0)
                .padding(.vertical, 16)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(brandGreen).frame(height: 2)
                }

                // Scorecard grid
                VStack(spacing: 0) {
                    scorecardRow(title: "Hole", values: Array(1...18).map { "\($0)" }, isHeader: true)
                    scorecardRow(title: "Par", values: pars.map { "\($0)" }, isHeader: false)
                    scorecardRow(title: "Score", values: round.scores.map { $0.map { "\($0)" } ?? "·" }, isHeader: false, highlightScores: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)

                Divider()
                    .padding(.horizontal, 16)

                // Totals
                HStack(spacing: 0) {
                    totalBlock(label: "Front 9", value: round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—")
                    totalBlock(label: "Back 9", value: round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
                    totalBlock(label: "Total", value: round.holesPlayed > 0 ? "\(round.totalScore)" : "—", highlight: true)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private func scorecardRow(title: String, values: [String], isHeader: Bool, highlightScores: Bool = false) -> some View {
        HStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(isHeader ? Color.white : Color(.secondaryLabel))
                .frame(width: 30, alignment: .leading)
                .padding(.leading, 4)
                .frame(height: 20)
                .background(isHeader ? brandGreen : Color.clear)

            ForEach(Array(zip(values.indices, values)), id: \.0) { index, value in
                Text(value)
                    .font(.system(size: 9, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? Color.white : scoreForeground(index: index, value: value))
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(isHeader ? brandGreen.opacity(0.85) : scoreBackground(index: index, value: value))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
    }

    private func scoreForeground(index: Int, value: String) -> Color {
        guard let score = Int(value), let par = pars[safe: index] else { return .primary }
        let diff = score - par
        switch diff {
        case ..<(-1): return Color(red: 0.7, green: 0.55, blue: 0.0)
        case -1:      return brandGreen
        case 1:       return Color.orange
        case 2...:    return Color.red
        default:      return .primary
        }
    }

    private func scoreBackground(index: Int, value: String) -> Color {
        guard let score = Int(value), let par = pars[safe: index] else { return Color.clear }
        let diff = score - par
        switch diff {
        case ..<(-1): return Color.yellow.opacity(0.2)
        case -1:      return brandGreen.opacity(0.2)
        case 1:       return Color.orange.opacity(0.15)
        case 2...:    return Color.red.opacity(0.15)
        default:      return Color.clear
        }
    }

    private func totalBlock(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(highlight ? brandGreen : .primary)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Minimal") {
    MinimalShareCard(round: {
        var r = Round(courseName: "Augusta National")
        r.scores = [5, 4, 4, 6, 5, 3, 4, 5, 6,
                    5, 3, 5, 6, 4, 3, 5, 6, 4]
        return r
    }())
    .frame(width: 280, height: 497)
    .clipShape(RoundedRectangle(cornerRadius: 20))
}

#Preview("Bold") {
    BoldShareCard(round: {
        var r = Round(courseName: "Augusta National")
        r.scores = [5, 4, 4, 6, 5, 3, 4, 5, 6,
                    5, 3, 5, 6, 4, 3, 5, 6, 4]
        return r
    }())
    .frame(width: 280, height: 497)
    .clipShape(RoundedRectangle(cornerRadius: 20))
}

#Preview("Scorecard") {
    ScorecardShareCard(round: {
        var r = Round(courseName: "Pebble Beach Golf Links")
        r.scores = [5, 4, 4, 6, 5, 3, 4, 5, 6,
                    5, 3, 5, 6, 4, 3, 5, 6, 4]
        return r
    }())
    .frame(width: 280, height: 497)
    .clipShape(RoundedRectangle(cornerRadius: 20))
}
