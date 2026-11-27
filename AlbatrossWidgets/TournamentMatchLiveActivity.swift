import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

struct TournamentMatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TournamentMatchActivity.self) { context in
            MatchLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.brandGreen)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamBadge(name: a.teamAName, colorHex: a.teamAColorHex, leading: s.lead > 0)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamBadge(name: a.teamBName, colorHex: a.teamBColorHex, leading: s.lead < 0)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Match \(a.matchNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.summary(for: a))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                Circle().fill(Color(matchHex: s.lead >= 0 ? a.teamAColorHex : a.teamBColorHex)).frame(width: 12, height: 12)
            } compactTrailing: {
                Text(s.shortLead)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Text(s.shortLead)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

// MARK: - Lock screen

private struct MatchLockScreenView: View {
    let attributes: TournamentMatchActivity
    let state: TournamentMatchActivity.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(attributes.tournamentName), match \(attributes.matchNumber)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                if !state.finished && state.holesPlayed > 0 {
                    Text("Thru \(state.holesPlayed)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            teamRow(name: attributes.teamAName, players: attributes.teamAPlayers, colorHex: attributes.teamAColorHex, leading: state.lead > 0)
            teamRow(name: attributes.teamBName, players: attributes.teamBPlayers, colorHex: attributes.teamBColorHex, leading: state.lead < 0)
            Text(state.summary(for: attributes))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(16)
    }

    private func teamRow(name: String, players: String, colorHex: String, leading: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color(matchHex: colorHex)).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(players).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer()
            if leading {
                Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(Color.brandGreenLight)
            }
        }
    }
}

private struct TeamBadge: View {
    let name: String
    let colorHex: String
    let leading: Bool

    var body: some View {
        VStack(spacing: 2) {
            Circle().fill(Color(matchHex: colorHex)).frame(width: 14, height: 14)
            Text(name).font(.caption.weight(leading ? .bold : .regular)).lineLimit(1)
        }
    }
}

private extension Color {
    /// "#RRGGBB" to a colour; anything else is grey.
    init(matchHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { self = .gray; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
