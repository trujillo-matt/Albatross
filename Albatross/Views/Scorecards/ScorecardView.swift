import SwiftUI

struct ScorecardView: View {
    @EnvironmentObject private var store: RoundStore
    @EnvironmentObject private var courseStore: CourseStore
    @Environment(\.dismiss) private var dismiss

    @State var round: Round
    var onFinish: (Round) -> Void
    var openNextHole: Bool = false

    @State private var selectedHole: Int? = nil
    @State private var showFinishConfirm = false
    @State private var showEditRound = false
    @State private var showCourseDetail = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var labelColumnWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 36

    private var pars: [Int] { round.effectivePars }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    courseHeaderCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    scorecardGrid
                        .padding(.horizontal, 16)

                    totalsCard
                        .padding(.horizontal, 16)

                    Color.clear.frame(height: 88)
                }
                .padding(.bottom, 16)
            }

            // Finish Round button pinned at bottom
            VStack(spacing: 0) {
                Divider()
                Button(action: { showFinishConfirm = true }) {
                    Text(round.isComplete ? "Finish Round" : "Finish Round (\(round.holesPlayed)/18)")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(round.holesPlayed > 0 ? Color.accentColor : Color.accentColor.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(round.holesPlayed == 0)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showEditRound = true }) {
                        Label("Edit Round", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: {
                        store.delete(round)
                        dismiss()
                    }) {
                        Label("Delete Round", systemImage: "trash")
                    }
                } label: {
                    Label("Round Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditRound) {
            EditRoundSheet(round: round) { updated in
                round = updated
            }
        }
        .sheet(isPresented: $showCourseDetail) {
            CourseDetailView(
                round: round,
                course: courseStore.allCourses.first(where: { $0.id == round.courseID })
            )
        }
        .sheet(isPresented: Binding(get: { selectedHole != nil }, set: { if !$0 { selectedHole = nil } })) {
            if let hole = selectedHole {
                ScoreInputView(
                    holeNumber: hole,
                    par: pars[hole - 1],
                    score: scoreBinding(for: hole - 1),
                    onConfirm: { saveRound() }
                )
            }
        }
        .confirmationDialog("Finish Round?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish Round") { finishRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if round.isComplete {
                Text("Your round is complete with a score of \(round.totalScore).")
            } else {
                Text("You've entered scores for \(round.holesPlayed) of 18 holes. You can still finish early.")
            }
        }
        .onAppear {
            if round.status == .inProgress {
                LiveActivityManager.shared.startActivity(for: round)
            }
            if openNextHole {
                // Small delay so the view is fully on screen before the sheet presents
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let nextIndex = round.scores.firstIndex(where: { $0 == nil }) ?? 0
                    selectedHole = nextIndex + 1
                }
            }
        }
    }

    // MARK: - Subviews

    private var courseHeaderCard: some View {
        HStack(spacing: 14) {
            // Course logo — shown when a logo was saved with the round
            courseLogoView

            Button(action: { showCourseDetail = true }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(round.courseName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(round.totalScore)")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(round.holesPlayed > 0 ? .primary : .tertiary)
                Text("total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var courseLogoView: some View {
        if let url = round.courseLogoURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
        }
        // If no logo, renders nothing (zero width) so layout is unchanged
    }

    @ViewBuilder
    private var scorecardGrid: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleHoleList
        } else {
            VStack(spacing: 0) {
                nineHoleSection(title: "Front 9", holeRange: 1...9)
                Divider().padding(.vertical, 8)
                nineHoleSection(title: "Back 9", holeRange: 10...18)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Nine columns cannot hold accessibility-size text, so each hole gets its own row.
    private var accessibleHoleList: some View {
        VStack(spacing: 0) {
            ForEach(1...18, id: \.self) { hole in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hole \(hole)")
                            .font(.body.weight(.semibold))
                        Text("Par \(pars[hole - 1])")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    scoreCell(hole: hole)
                        .frame(maxWidth: 120)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if hole < 18 { Divider() }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func nineHoleSection(title: String, holeRange: ClosedRange<Int>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)
                    .padding(.leading, 12)

                ForEach(Array(holeRange), id: \.self) { hole in
                    Text("\(hole)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground))

            HStack(spacing: 0) {
                Text("Par")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)
                    .padding(.leading, 12)

                ForEach(Array(holeRange), id: \.self) { hole in
                    Text("\(pars[hole - 1])")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 8)

            HStack(spacing: 0) {
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)
                    .padding(.leading, 12)

                ForEach(Array(holeRange), id: \.self) { hole in
                    scoreCell(hole: hole)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func scoreCell(hole: Int) -> some View {
        let index = hole - 1
        let score = round.scores[index]
        let par = pars[index]
        let diff = score.map { $0 - par }
        let isAlbatross = score == 2 && par == 5

        return Button(action: { selectedHole = hole }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cellBackground(diff: diff))
                    .frame(height: cellHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(cellBorder(diff: diff), lineWidth: score != nil ? 1.5 : 1)
                    )

                if isAlbatross {
                    Image("black-browed-albatross")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else if let s = score {
                    Text("\(s)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(cellForeground(diff: diff))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Hole \(hole), par \(par)")
        .accessibilityValue(score.map { "\($0)" } ?? "No score")
    }

    private func cellBackground(diff: Int?) -> Color {
        guard let diff else { return Color(.tertiarySystemGroupedBackground) }
        switch diff {
        case ..<(-1): return Color.yellow.opacity(0.15)
        case -1:      return Color.accentColor.opacity(0.15)
        case 0:       return Color(.tertiarySystemGroupedBackground)
        case 1:       return Color.orange.opacity(0.12)
        default:      return Color.red.opacity(0.12)
        }
    }

    private func cellBorder(diff: Int?) -> Color {
        guard let diff else { return Color(.separator) }
        switch diff {
        case ..<(-1): return Color.yellow.opacity(0.6)
        case -1:      return Color.accentColor.opacity(0.6)
        case 0:       return Color(.separator)
        case 1:       return Color.orange.opacity(0.5)
        default:      return Color.red.opacity(0.5)
        }
    }

    private func cellForeground(diff: Int?) -> Color {
        guard let diff else { return .primary }
        switch diff {
        case ..<(-1): return Color.yellow
        case -1:      return Color.accentColor
        case 0:       return .primary
        case 1:       return Color.orange
        default:      return Color.red
        }
    }

    private var totalsCard: some View {
        HStack(spacing: 0) {
            totalColumn(label: "Front 9", value: round.frontNineTotal, played: round.scores.prefix(9).compactMap { $0 }.count)
            Divider().frame(height: 40)
            totalColumn(label: "Back 9", value: round.backNineTotal, played: round.scores.suffix(9).compactMap { $0 }.count)
            Divider().frame(height: 40)
            totalColumn(label: "Total", value: round.totalScore, played: round.holesPlayed, isTotal: true)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func totalColumn(label: String, value: Int, played: Int, isTotal: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(played > 0 ? "\(value)" : "—")
                .font(.system(size: isTotal ? 22 : 18, weight: .semibold))
                .foregroundStyle(isTotal && played > 0 ? Color.accentColor : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func scoreBinding(for index: Int) -> Binding<Int?> {
        Binding(
            get: { round.scores[index] },
            set: { round.scores[index] = $0 }
        )
    }

    private func saveRound() {
        store.update(round)
        LiveActivityManager.shared.updateActivity(for: round)
    }

    private func finishRound() {
        round.status = .completed
        store.update(round)
        LiveActivityManager.shared.endActivity(for: round)
        onFinish(round)
    }
}

#Preview {
    NavigationStack {
        ScorecardView(round: Round(courseName: "Pebble Beach"), onFinish: { _ in })
            .environmentObject(RoundStore())
    }
}
