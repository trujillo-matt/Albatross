import SwiftUI

/// Modal number-pad style score entry for a single hole.
struct ScoreInputView: View {
    let holeNumber: Int
    let par: Int
    @Binding var score: Int?
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var inputText: String = ""

    @State private var viewportHeight: CGFloat = 0

    /// The sheet's height varies with the device, its orientation and the text size.
    /// The content scrolls when it cannot fit, and stretches to fill the sheet when
    /// there is spare room, so the number pad keys are never squashed or cut off.
    private func scrollingWhenNeeded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(minHeight: viewportHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    }

    private var parsedScore: Int? {
        guard let v = Int(inputText), v >= 1, v <= 20 else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            scrollingWhenNeeded {
            VStack(spacing: 0) {
                // Header — tapping here commits + dismisses (acts as "save")
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        Text("Hole \(holeNumber)")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(Color(.separator))
                            .frame(width: 4, height: 4)

                        Text("Par \(par)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .center, spacing: 6) {
                        Text(inputText.isEmpty ? (score.map { String($0) } ?? "—") : inputText)
                            .scaledFont(size: 72, weight: .semibold)
                            // The value is a large display figure; scaling it further only crowds the keys.
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(scoreDisplayColor)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: inputText)

                        if !inputText.isEmpty || score != nil {
                            Button { clearScore() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .scaledFont(size: 22)
                                    .foregroundStyle(Color(.tertiaryLabel))
                                    .accessibilityLabel("Clear Score")
                            }
                            .offset(y: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .background(Color(.systemGroupedBackground))
                // Tap header area to save
                .contentShape(Rectangle())
                .onTapGesture { commit() }

                Divider()

                // Number pad
                NumberPadView(inputText: $inputText, par: par, onCommit: commit)
                    .background(Color(.systemGroupedBackground))
            }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }
            .onAppear {
                if let existing = score {
                    inputText = String(existing)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // With room to spare the sheet slides in from the side, so the scorecard stays visible.
        .sidePlacementWhenWide(horizontalSizeClass == .regular)
        .presentationDragIndicator(.visible)
        // Drag-to-dismiss also commits the score
        .onDisappear {
            if let v = parsedScore {
                score = v
                onConfirm()
            }
        }
    }

    // MARK: - Colours

    private var scoreDisplayColor: Color {
        guard let v = parsedScore ?? score else { return .secondary }
        let diff = v - par
        if diff == 0 { return .primary }
        return keyColor(for: v, par: par)
    }

    private func commit() {
        if let v = parsedScore {
            score = v
        }
        onConfirm()
        dismiss()
    }

    private func clearScore() {
        inputText = ""
        score = nil
        onConfirm()
        dismiss()
    }
}

// MARK: - Number pad

private struct NumberPadView: View {
    @Binding var inputText: String
    let par: Int
    var onCommit: () -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", ""]
    ]

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    @ScaledMetric(relativeTo: .title2) private var keyMinHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: keyMinHeight, maxHeight: keyMinHeight * 1.8)
                        } else {
                            Button(action: { handleKey(key) }) {
                                keyLabel(key)
                                    .frame(maxWidth: .infinity, minHeight: keyMinHeight, maxHeight: keyMinHeight * 1.8)
                            }
                            .buttonStyle(KeyButtonStyle(key: key, par: par))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        // Keys stay a tappable size in wide sheets instead of stretching with them.
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func keyLabel(_ key: String) -> some View {
        if key == "⌫" {
            Image(systemName: "delete.backward")
                .scaledFont(size: 20)
                .foregroundStyle(.primary)
        } else {
            Text(key)
                .font(.title2)
                .foregroundStyle(keyTextColor(key))
        }
    }

    private func keyTextColor(_ key: String) -> Color {
        guard let v = Int(key) else { return .primary }
        let diff = v - par
        if diff == 0 { return .primary }
        return keyColor(for: v, par: par)
    }

    private func handleKey(_ key: String) {
        haptic.impactOccurred()

        if key == "⌫" {
            if !inputText.isEmpty { inputText.removeLast() }
            return
        }

        let candidate = inputText + key

        if let v = Int(candidate), v >= 1, v <= 20 {
            inputText = candidate
            if candidate.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onCommit()
                }
            }
        } else if inputText.isEmpty, key == "0" {
            // Don't allow leading zero
        }
    }
}

// MARK: - Key colour helper

func keyColor(for score: Int, par: Int) -> Color {
    let diff = score - par
    switch diff {
    case ..<(-1): return .blue
    case -1:      return Color.accentColor
    case 0:       return .primary
    case 1:       return Color(red: 0.95, green: 0.35, blue: 0.25)
    default:      return Color(red: 0.80, green: 0.12, blue: 0.12)
    }
}

// MARK: - Key button style

private struct KeyButtonStyle: ButtonStyle {
    let key: String
    let par: Int

    func makeBody(configuration: Configuration) -> some View {
        let isDelete = key == "⌫"
        let score = Int(key)
        let color = score.map { keyColor(for: $0, par: par) }
        let isParKey = score == par
        let hasTint = !isDelete && !isParKey && score != nil

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    hasTint
                        ? (color ?? Color(.secondarySystemGroupedBackground)).opacity(configuration.isPressed ? 0.5 : 0.18)
                        : Color(.secondarySystemGroupedBackground).opacity(configuration.isPressed ? 0.5 : 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)

            if hasTint {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        (color ?? Color.clear).opacity(0.45),
                        lineWidth: 1.5
                    )
            }

            configuration.label
        }
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ScoreInputView(holeNumber: 3, par: 4, score: .constant(nil), onConfirm: {})
}
