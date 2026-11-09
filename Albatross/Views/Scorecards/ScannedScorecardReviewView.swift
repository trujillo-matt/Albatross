import SwiftUI

/// Shown after the scorecard scanner processes an image.
/// Lets the user pick their player row, review all 18 scores,
/// tap to correct any cell, and confirm to create the round.
struct ScannedScorecardReviewView: View {
    let result: ScorecardParseResult
    var onConfirm: (_ scores: [Int?], _ courseName: String) -> Void
    var onCancel: () -> Void

    @State private var selectedRowIndex: Int = 0
    @State private var editedScores: [Int?] = Array(repeating: nil, count: 18)
    @State private var editingHole: Int? = nil
    @State private var courseNameInput: String = ""

    private var effectivePars: [Int] {
        result.pars ?? [4, 4, 3, 4, 5, 3, 4, 4, 5,
                        4, 3, 4, 5, 4, 3, 4, 5, 4]
    }

    private var isConfirmEnabled: Bool {
        !courseNameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        courseNameField

                        if result.playerRows.count > 1 {
                            playerPicker
                        }

                        if result.playerRows.isEmpty {
                            noScoresDetectedNote
                        }

                        nineGrid(title: "Front 9", range: 0..<9)
                        nineGrid(title: "Back 9", range: 9..<18)

                        totalsRow
                        confirmButton
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Review Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }
            // ScoreInputView sheet for correcting individual cells
            .sheet(isPresented: Binding(
                get: { editingHole != nil },
                set: { if !$0 { editingHole = nil } }
            )) {
                if let hole = editingHole {
                    ScoreInputView(
                        holeNumber: hole,
                        par: effectivePars[hole - 1],
                        score: $editedScores[hole - 1],
                        onConfirm: {
                            // Capture whether a real score was just confirmed (not cleared)
                            let confirmedScore = editedScores[hole - 1]
                            let nextHole = hole + 1
                            editingHole = nil
                            // Auto-advance: only if a score was entered AND the next hole is still blank
                            if confirmedScore != nil,
                               nextHole <= 18,
                               editedScores[nextHole - 1] == nil {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    editingHole = nextHole
                                }
                            }
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .onAppear {
                courseNameInput = result.courseName ?? ""
                loadSelectedRow()
            }
            .onChange(of: selectedRowIndex) { _, _ in
                loadSelectedRow()
            }
        }
    }

    // MARK: - Subviews

    private var courseNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Course Name")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            TextField("e.g. Pebble Beach", text: $courseNameInput)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
    }

    private var playerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select your row")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Picker("Player", selection: $selectedRowIndex) {
                ForEach(result.playerRows.indices, id: \.self) { index in
                    Text(result.playerRows[index].label)
                        .tag(index)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
    }

    private var noScoresDetectedNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            Text("No scores detected — tap any cell to enter manually")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private func nineGrid(title: String, range: Range<Int>) -> some View {
        let subtotal = editedScores[range].compactMap { $0 }.reduce(0, +)
        let filledCount = editedScores[range].compactMap { $0 }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if filledCount > 0 {
                    Text("\(subtotal)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                // Hole number row
                HStack(spacing: 4) {
                    ForEach(range, id: \.self) { i in
                        Text("\(i + 1)")
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                            .frame(maxWidth: .infinity)
                    }
                }

                // Par row
                HStack(spacing: 4) {
                    ForEach(range, id: \.self) { i in
                        Text("P\(effectivePars[i])")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Score cells
                HStack(spacing: 4) {
                    ForEach(range, id: \.self) { i in
                        scoreCell(holeIndex: i)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
    }

    private func scoreCell(holeIndex: Int) -> some View {
        let score = editedScores[holeIndex]
        let par = effectivePars[holeIndex]

        return Button(action: { editingHole = holeIndex + 1 }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(score == nil
                          ? Color(.tertiarySystemFill)
                          : cellBackground(score: score!, par: par))

                if let score {
                    Text("\(score)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cellForeground(score: score, par: par))
                } else {
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
    }

    private var totalsRow: some View {
        let filled = editedScores.compactMap { $0 }
        let total = filled.reduce(0, +)
        let par = effectivePars.reduce(0, +)
        let diff = total - par

        return Group {
            if !filled.isEmpty {
                HStack {
                    Text("\(filled.count) of 18 holes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if filled.count == 18 {
                        let diffText = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
                        Text("Total: \(total)  (\(diffText))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("Total so far: \(total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var confirmButton: some View {
        Button(action: confirm) {
            Text("Confirm & Save Round")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isConfirmEnabled ? Color.accentColor : Color.accentColor.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isConfirmEnabled)
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func loadSelectedRow() {
        guard !result.playerRows.isEmpty,
              selectedRowIndex < result.playerRows.count else {
            editedScores = Array(repeating: nil, count: 18)
            return
        }
        editedScores = result.playerRows[selectedRowIndex].scores
    }

    private func confirm() {
        let name = courseNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onConfirm(editedScores, name)
    }

    // MARK: - Cell Colors (matching ScorecardView conventions)

    private func cellBackground(score: Int, par: Int) -> Color {
        switch score - par {
        case ...(-2): return Color.yellow.opacity(0.80)
        case -1:      return Color.blue.opacity(0.80)
        case 0:       return Color(.secondarySystemFill)
        case 1:       return Color.orange.opacity(0.80)
        default:      return Color.red.opacity(0.80)
        }
    }

    private func cellForeground(score: Int, par: Int) -> Color {
        score - par == 0 ? Color(.label) : .white
    }
}
