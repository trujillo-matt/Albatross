import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

struct AlbatrossLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlbatrossLiveActivity.self) { context in
            // Lock screen / notification banner
            AlbatrossLockScreenView(
                courseName: context.attributes.courseAbbreviation,
                state: context.state
            )
            .activityBackgroundTint(Color(red: 0.13, green: 0.17, blue: 0.13))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "albatross://round?id=\(context.attributes.roundID)"))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (user long-presses the island)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                        Text(context.attributes.courseName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(scoreToParString(context.state.scoreToPar))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreToParColor(context.state.scoreToPar))
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HoleStripView(scores: context.state.scores, pars: context.state.pars)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }

            } compactLeading: {
                // Flag + score-to-par
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(scoreToParString(context.state.scoreToPar))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreToParColor(context.state.scoreToPar))
                }

            } compactTrailing: {
                // "Hole 7" or "Thru 18"
                Text(holeLabel(context.state.holesPlayed))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

            } minimal: {
                // Minimal: just score-to-par
                Text(scoreToParString(context.state.scoreToPar))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreToParColor(context.state.scoreToPar))
            }
            .widgetURL(URL(string: "albatross://round?id=\(context.attributes.roundID)"))
            .keylineTint(.green)
        }
    }
}

// MARK: - Lock Screen View

struct AlbatrossLockScreenView: View {
    let courseName: String
    let state: AlbatrossLiveActivity.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: course name + score-to-par
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(courseName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(scoreToParString(state.scoreToPar))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreToParColor(state.scoreToPar))

                    Text(state.holesPlayed == 0
                         ? "vs par"
                         : state.holesPlayed == 18 ? "final" : "thru \(state.holesPlayed)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // 18-hole strip
            HoleStripView(scores: state.scores, pars: state.pars)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Hole Strip

struct HoleStripView: View {
    let scores: [Int]   // 18 elements, -1 = not yet played
    let pars: [Int]     // 18 elements

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<18, id: \.self) { index in
                let score = index < scores.count ? scores[index] : -1
                let par   = index < pars.count   ? pars[index]   : 4

                holeDot(score: score, par: par, index: index)

                // Subtle divider between front/back 9
                if index == 8 {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 3)
                }
            }
        }
    }

    private func holeDot(score: Int, par: Int, index: Int) -> some View {
        let color = holeColor(score: score, par: par)
        let isPlayed = score != -1

        return Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(
                Circle()
                    .strokeBorder(isPlayed ? color : Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared Helpers

func scoreToParString(_ scoreToPar: Int) -> String {
    switch scoreToPar {
    case 0:          return "E"
    case let n where n > 0: return "+\(n)"
    default:         return "\(scoreToPar)"
    }
}

func scoreToParColor(_ scoreToPar: Int) -> Color {
    switch scoreToPar {
    case ..<0:  return Color.green
    case 0:     return Color.white
    case 1:     return Color.orange
    default:    return Color.red
    }
}

func holeLabel(_ holesPlayed: Int) -> String {
    if holesPlayed == 0  { return "Hole 1" }
    if holesPlayed == 18 { return "Thru 18" }
    return "Hole \(holesPlayed)"
}

func holeColor(score: Int, par: Int) -> Color {
    if score == -1 { return Color.white.opacity(0.15) }
    let diff = score - par
    switch diff {
    case ..<(-1): return Color.yellow        // eagle or better
    case -1:      return Color.green         // birdie
    case 0:       return Color.white.opacity(0.45)  // par
    case 1:       return Color.orange        // bogey
    default:      return Color.red           // double bogey+
    }
}

// MARK: - Previews

extension AlbatrossLiveActivity.ContentState {
    static var previewFrontNine: Self {
        // 4 holes played: birdie, par, bogey, birdie
        var scores = Array(repeating: -1, count: 18)
        let pars   = [4,4,3,4,5,3,4,4,5, 4,3,4,5,4,3,4,5,4]
        scores[0] = 3  // birdie
        scores[1] = 4  // par
        scores[2] = 4  // bogey on par-3
        scores[3] = 3  // birdie
        return Self(scores: scores, pars: pars, holesPlayed: 4, totalStrokes: 14, scoreToPar: -2)
    }

    static var previewComplete: Self {
        let pars   = [4,4,3,4,5,3,4,4,5, 4,3,4,5,4,3,4,5,4]
        let scores = [4,3,3,4,5,3,4,5,5, 4,3,4,4,4,3,4,5,4]
        return Self(scores: scores, pars: pars, holesPlayed: 18, totalStrokes: 71, scoreToPar: -1)
    }
}

#Preview("Lock Screen", as: .content, using: AlbatrossLiveActivity(
    courseName: "Pebble Beach Golf Links",
    courseAbbreviation: "Pebble Bch GL",
    roundID: UUID()
)) {
    AlbatrossLiveActivityWidget()
} contentStates: {
    AlbatrossLiveActivity.ContentState.previewFrontNine
    AlbatrossLiveActivity.ContentState.previewComplete
}
