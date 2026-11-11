import Charts
import SwiftUI

/// The player's game in numbers, drawn from every finished 18-hole round.
struct StatsView: View {
    @EnvironmentObject private var store: RoundStore
    @EnvironmentObject private var appearance: CardAppearance
    @Environment(\.colorScheme) private var colorScheme

    private var stats: RoundStats { RoundStats(rounds: store.rounds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if stats.isEmpty {
                        emptyState
                    } else {
                        dashboard(stats)
                    }
                }
                .padding(16)
                .readableContentWidth(920)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("No finished rounds yet")
                .font(.title3.weight(.semibold))
            Text("Finish an 18-hole round and your scoring, putting and course records appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dashboard

    private func dashboard(_ stats: RoundStats) -> some View {
        VStack(spacing: 16) {
            overview(stats)
            trend(stats)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                scoring(stats)
                byParType(stats)
                putting(stats)
                records(stats)
                courses(stats)
            }
        }
    }

    // MARK: Overview

    private func overview(_ stats: RoundStats) -> some View {
        DashboardCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .leading)], spacing: 16) {
                figure(
                    "Handicap index",
                    stats.handicap.map { String(format: "%.1f", $0) } ?? "—",
                    note: stats.handicap == nil ? "Needs 3 rounds" : nil)
                figure(
                    "Average",
                    stats.averageScore.map { String(format: "%.1f", $0) } ?? "—",
                    note: stats.recentChange.map { change in
                        let sign = change < 0 ? "−" : "+"
                        return "\(sign)\(String(format: "%.1f", abs(change))) vs previous 5"
                    },
                    noteColor: (stats.recentChange ?? 0) <= 0 ? .accentColor : .secondary)
                figure(
                    "Best round",
                    stats.bestRound.map { "\($0.totalScore)" } ?? "—",
                    note: stats.bestRound?.courseName)
                figure("Rounds", "\(stats.count)", note: "\(stats.holesPlayed) holes")
            }
        }
    }

    private func figure(_ label: String, _ value: String, note: String? = nil, noteColor: Color = .secondary, large: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font((large ? Font.largeTitle : Font.title2).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Every figure keeps a note line, so a row of figures lines up whether or not they have notes.
            Text(note ?? " ")
                .font(.caption)
                .foregroundStyle(noteColor)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Trend

    private func trend(_ stats: RoundStats) -> some View {
        let recent = stats.recent
        let scores = recent.map(\.totalScore)
        let low = (scores.min() ?? 70) - 4
        let high = (scores.max() ?? 100) + 4
        return DashboardCard(title: "Score by round", subtitle: "Last \(recent.count) rounds, oldest to newest") {
            Chart {
                ForEach(Array(recent.enumerated()), id: \.offset) { index, round in
                    LineMark(x: .value("Round", index + 1), y: .value("Score", round.totalScore))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Round", index + 1), y: .value("Score", round.totalScore))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(recent.count > 12 ? 24 : 44)
                }
                if let average = stats.averageScore {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Average \(String(format: "%.1f", average))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: low...high)
            .chartXScale(domain: 1...max(2, recent.count))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color(.secondaryLabel))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color(.secondaryLabel))
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Score by round")
            .accessibilityValue(scores.map(String.init).joined(separator: ", "))
        }
    }

    // MARK: Scoring

    private func scoring(_ stats: RoundStats) -> some View {
        let distribution = stats.distribution()
        let total = max(1, distribution.reduce(0) { $0 + $1.count })
        return DashboardCard(title: "Every hole", subtitle: "\(stats.holesPlayed) holes played") {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(distribution, id: \.result) { entry in
                            if entry.count > 0 {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(ink(entry.result))
                                    .frame(width: max(4, proxy.size.width * CGFloat(entry.count) / CGFloat(total)))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    ForEach(distribution, id: \.result) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(ink(entry.result)).frame(width: 8, height: 8)
                            Text(entry.result.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(entry.count)")
                                .font(.subheadline.monospacedDigit())
                            Text(percent(entry.count, of: total))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func ink(_ result: RoundStats.Result) -> Color {
        BookletStyle.ink(forDifference: result.difference, onDark: colorScheme == .dark)
    }

    private func percent(_ count: Int, of total: Int) -> String {
        "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }

    // MARK: By par type

    private func byParType(_ stats: RoundStats) -> some View {
        let rows = stats.byParType()
        let best = rows.map(\.average).min()
        let scale = max(1.0, rows.map(\.average).max() ?? 1)
        return DashboardCard(title: "By hole length", subtitle: "Average strokes over par") {
            VStack(spacing: 12) {
                ForEach(rows, id: \.par) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Par \(row.par)")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%+.2f", row.average))
                                .font(.subheadline.monospacedDigit().weight(.medium))
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(row.average == best ? Color.brandGreen : Color.primary.opacity(0.35))
                                        .frame(width: max(6, proxy.size.width * CGFloat(max(0, row.average) / scale)))
                                }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Putting

    @ViewBuilder
    private func putting(_ stats: RoundStats) -> some View {
        DashboardCard(title: "Putting and greens", subtitle: "Rounds with putts recorded") {
            if stats.hasPuttingData {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12, alignment: .leading)], spacing: 12) {
                    figure("Putts a round", stats.averagePuttsPerRound.map { String(format: "%.1f", $0) } ?? "—", large: false)
                    figure("Putts a hole", stats.averagePuttsPerHole.map { String(format: "%.2f", $0) } ?? "—", large: false)
                    figure("Greens", stats.greenInRegulationRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", large: false)
                }
            } else {
                Text(appearance.tracksPuttsAndGreens
                     ? "Add putts and greens as you play and the averages appear here."
                     : "Putts and greens are switched off. Turn them on in Settings, under Scorecard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Records

    private func records(_ stats: RoundStats) -> some View {
        DashboardCard(title: "Records") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12, alignment: .leading)], spacing: 12) {
                figure("Best front nine", stats.bestFrontNine.map(String.init) ?? "—", large: false)
                figure("Best back nine", stats.bestBackNine.map(String.init) ?? "—", large: false)
                figure("Most birdies", stats.mostBirdiesInARound.map(String.init) ?? "—", note: "in one round", large: false)
                figure("Birdies or better", "\(stats.totalBirdiesOrBetter)", note: "all rounds", large: false)
            }
        }
    }

    // MARK: Courses

    private func courses(_ stats: RoundStats) -> some View {
        let list = Array(stats.courses().prefix(5))
        let most = max(1, list.map(\.rounds).max() ?? 1)
        return DashboardCard(title: "Courses", subtitle: "Most played") {
            VStack(spacing: 12) {
                ForEach(list) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(course.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("Best \(course.best)")
                                .font(.subheadline.monospacedDigit().weight(.medium))
                        }
                        HStack {
                            Text("\(course.rounds) \(course.rounds == 1 ? "round" : "rounds") · average \(String(format: "%.1f", course.average))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.35))
                                        .frame(width: max(6, proxy.size.width * CGFloat(course.rounds) / CGFloat(most)))
                                }
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A quiet surface for one group of numbers.
struct DashboardCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    StatsView()
        .environmentObject({
            let store = RoundStore()
            for index in 0..<8 {
                var round = Round(courseName: index % 3 == 0 ? "Pebble Beach" : "Augusta National")
                round.date = Date().addingTimeInterval(Double(-index) * 86_400 * 6)
                round.scores = (0..<18).map { 3 + (($0 + index) % 4) }
                round.status = .completed
                store.add(round)
            }
            return store
        }())
        .environmentObject(CardAppearance())
}
