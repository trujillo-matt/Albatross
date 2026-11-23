import SwiftUI

// MARK: - Logo loader helper

/// Loads the course logo UIImage from disk synchronously.
/// Called before ImageRenderer so the image is ready at render time.
func loadCourseLogo(for round: Round) -> UIImage? {
    guard let url = round.courseLogoURL,
          let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}

/// The player's paper and ink, resolved once so a rendered image never depends on the environment.
/// Color.accentColor does not resolve inside ImageRenderer, so every color here is explicit.
struct ShareStyle {
    let paper: Color
    let ink: Color
    let includesPutts: Bool

    @MainActor
    init(appearance: CardAppearance, round: Round) {
        paper = appearance.pageColor(for: round)
        ink = appearance.ink(for: round)
        includesPutts = appearance.tracksPuttsAndGreens && round.totalPutts != nil
    }
}

private func toPar(_ round: Round) -> String {
    let played = zip(round.scores, round.effectivePars).reduce(0) { $0 + ($1.0 == nil ? 0 : $1.1) }
    let difference = round.totalScore - played
    if difference == 0 { return "E" }
    return difference > 0 ? "+\(difference)" : "−\(abs(difference))"
}

private struct ShareFooter: View {
    var color: Color = Color(.secondaryLabel)

    var body: some View {
        HStack(spacing: 6) {
            Image("black-browed-albatross")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text("Albatross")
                .appFont(.small)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Template 1: the cover

/// The booklet cover on a quiet table, the way it sits on the shelf.
struct CoverShareCard: View {
    let round: Round
    let style: ShareStyle
    let appearance: CardAppearance

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.93, blue: 0.91)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                CourseCoverView(round: round)
                    .environmentObject(appearance)
                    .frame(width: 296, height: 411)
                Spacer(minLength: 0)
                ShareFooter()
                    .padding(.bottom, 28)
            }
        }
    }
}

// MARK: - Template 2: the scorecard

/// Both nines on the club's printed card, with putts and greens when they were recorded.
struct ScorecardShareCard: View {
    let round: Round
    let style: ShareStyle
    var logoImage: UIImage? = nil

    private var pars: [Int] { round.effectivePars }

    var body: some View {
        ZStack {
            style.paper
            VStack(spacing: 20) {
                banner
                nine(1...9, totalLabel: "Out")
                nine(10...18, totalLabel: "In")
                summary
                Spacer(minLength: 0)
                ShareFooter()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
        }
    }

    private var banner: some View {
        VStack(spacing: 4) {
            Text(round.courseName)
                .appFont(.body, weight: .semibold)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(round.date.formatted(date: .long, time: .omitted))
                .appFont(.small)
                .foregroundStyle(Color(.secondaryLabel))
            VStack(spacing: 2) {
                Rectangle().fill(style.ink).frame(height: 1.5)
                Rectangle().fill(style.ink.opacity(0.5)).frame(height: 0.5)
            }
            .padding(.top, 4)
        }
    }

    private func nine(_ holes: ClosedRange<Int>, totalLabel: String) -> some View {
        VStack(spacing: 0) {
            line("Hole", holes: holes, background: style.ink, height: 28) { hole in
                Text("\(hole)").appFont(.small, weight: .semibold).foregroundStyle(.white)
            } total: {
                Text(totalLabel).appFont(.small, weight: .semibold).textCase(.uppercase).foregroundStyle(.white)
            }
            line("Par", holes: holes, height: 28) { hole in
                Text("\(pars[hole - 1])").appFont(.small).foregroundStyle(.primary)
            } total: {
                Text("\(holes.reduce(0) { $0 + pars[$1 - 1] })").appFont(.small).foregroundStyle(.primary)
            }
            line("Score", holes: holes, height: 46) { hole in
                ScoreMark(score: round.scores[hole - 1], par: pars[hole - 1], side: 26, isActive: false, accent: style.ink)
            } total: {
                Text(total(holes).map(String.init) ?? "—")
                    .font(.custom(BookletStyle.pencilFontName, fixedSize: 17))
                    .foregroundStyle(BookletStyle.pencilGraphite)
            }
            if style.includesPutts {
                line("Putt", holes: holes, height: 28) { hole in
                    Text(round.putts(on: hole).map(String.init) ?? "")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 13))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                } total: {
                    Text(round.puttsTotal(holes).map(String.init) ?? "—")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 13))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                }
                line("GIR", holes: holes, height: 28) { hole in
                    Group {
                        switch round.greenInRegulation(on: hole) {
                        case true?:  Circle().fill(style.ink).frame(width: 8, height: 8)
                        case false?: Circle().strokeBorder(style.ink.opacity(0.45), lineWidth: 1).frame(width: 8, height: 8)
                        case nil:    Color.clear.frame(width: 8, height: 8)
                        }
                    }
                } total: {
                    let greens = round.greens(holes)
                    Text(greens.known > 0 ? "\(greens.hit)" : "—")
                        .font(.custom(BookletStyle.pencilFontName, fixedSize: 13))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(style.ink, lineWidth: 1))
    }

    private func total(_ holes: ClosedRange<Int>) -> Int? {
        let played = holes.compactMap { round.scores[$0 - 1] }
        return played.isEmpty ? nil : played.reduce(0, +)
    }

    private func line<Cell: View, Total: View>(
        _ label: String,
        holes: ClosedRange<Int>,
        background: Color = .clear,
        height: CGFloat,
        @ViewBuilder cell: @escaping (Int) -> Cell,
        @ViewBuilder total: () -> Total
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .appFont(.small, weight: .semibold)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(background == .clear ? style.ink : Color.white)
                .frame(width: 46)
            ForEach(Array(holes), id: \.self) { hole in
                cell(hole)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) { Rectangle().fill(style.ink.opacity(0.25)).frame(width: 0.5) }
            }
            total()
                .frame(width: 40, height: height)
                .overlay(alignment: .leading) { Rectangle().fill(style.ink.opacity(0.25)).frame(width: 0.5) }
        }
        .frame(height: height)
        .background(background)
        .overlay(alignment: .bottom) { Rectangle().fill(style.ink.opacity(0.25)).frame(height: 0.5) }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(round.totalScore)")
                .font(.custom(BookletStyle.pencilFontName, fixedSize: 64))
                .foregroundStyle(BookletStyle.pencilGraphite)
            VStack(alignment: .leading, spacing: 2) {
                Text(toPar(round))
                    .font(.custom(BookletStyle.pencilFontName, fixedSize: 22))
                    .foregroundStyle(BookletStyle.pencilGraphite)
                Text(detail)
                    .appFont(.small)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
        }
    }

    private var detail: String {
        var parts = ["\(round.holesPlayed) holes"]
        if style.includesPutts, let putts = round.totalPutts { parts.append("\(putts) putts") }
        let greens = round.greens()
        if style.includesPutts, greens.known > 0 { parts.append("\(greens.hit)/\(greens.known) greens") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Template 3: the score

/// One number, big, with where and when.
struct ScoreShareCard: View {
    let round: Round
    let style: ShareStyle
    var logoImage: UIImage? = nil

    var body: some View {
        ZStack {
            style.paper
            VStack(spacing: 0) {
                Rectangle().fill(style.ink).frame(height: 8)
                Spacer()
                VStack(spacing: 20) {
                    if let logo = logoImage {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    }
                    VStack(spacing: 0) {
                        Text("\(round.totalScore)")
                            .font(.custom(BookletStyle.pencilFontName, fixedSize: 150))
                            .foregroundStyle(BookletStyle.pencilGraphite)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(toPar(round))
                            .font(.custom(BookletStyle.pencilFontName, fixedSize: 32))
                            .foregroundStyle(BookletStyle.pencilGraphite)
                    }
                    VStack(spacing: 6) {
                        Text(round.courseName)
                            .appFont(.large, weight: .semibold)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(style.ink)
                            .multilineTextAlignment(.center)
                        Text(round.date.formatted(date: .long, time: .omitted))
                            .appFont(.small)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .padding(.horizontal, 32)
                }
                Spacer()
                HStack(spacing: 0) {
                    stat("Out", round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—")
                    stat("In", round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
                    if style.includesPutts, let putts = round.totalPutts { stat("Putts", "\(putts)") }
                    let greens = round.greens()
                    if style.includesPutts, greens.known > 0 { stat("Greens", "\(greens.hit)/\(greens.known)") }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(style.ink.opacity(0.3)).frame(height: 0.5) }
                .padding(.horizontal, 24)
                ShareFooter()
                    .padding(.vertical, 22)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .appFont(.large, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .appFont(.small)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }
}
