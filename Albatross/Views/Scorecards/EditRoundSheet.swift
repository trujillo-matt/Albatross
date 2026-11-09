import SwiftUI
import PhotosUI

struct EditRoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RoundStore

    @State private var round: Round
    @State private var pars: [Int]

    // Logo state
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var logoImage: UIImage? = nil
    @State private var didChangeLogo = false

    var onSave: (Round) -> Void

    init(round: Round, onSave: @escaping (Round) -> Void) {
        _round = State(initialValue: round)
        _pars  = State(initialValue: round.effectivePars)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Logo
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let img = logoImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image("black-browed-albatross")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 44, height: 44)
                                                .opacity(0.7)
                                        )
                                }

                                Circle()
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                    )
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)

                    if logoImage != nil {
                        Button(role: .destructive) {
                            logoImage = nil
                            didChangeLogo = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove Logo")
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Course Logo")
                        .font(.caption)
                }

                // MARK: Course info
                Section {
                    LabeledContent("Course") {
                        TextField("Course name", text: $round.courseName)
                            .font(.callout)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker(
                        "Date",
                        selection: $round.date,
                        displayedComponents: .date
                    )
                    .font(.callout)
                } header: {
                    Text("Round Info")
                        .font(.caption)
                }

                // MARK: Per-hole pars
                Section {
                    nineHolePars(range: 0..<9)
                } header: {
                    Text("Front 9 Pars")
                        .font(.caption)
                }

                Section {
                    nineHolePars(range: 9..<18)
                } header: {
                    Text("Back 9 Pars")
                        .font(.caption)
                }

                if round.courseID != nil {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                            Text("Pars were loaded from the course database. Any changes you make here will override them for this round only.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Edit Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .albatrossConfirm) {
                    Button { save() } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                }
            }
            .onAppear {
                logoImage = loadCourseLogo(for: round)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        logoImage = image
                        didChangeLogo = true
                    }
                }
            }
        }
    }

    // MARK: - Nine-hole par grid

    private func nineHolePars(range: Range<Int>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(range, id: \.self) { index in
                    Text("\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                ForEach(range, id: \.self) { index in
                    parCell(index: index)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func parCell(index: Int) -> some View {
        VStack(spacing: 4) {
            // UP = increment
            Button(action: { if pars[index] < 5 { pars[index] += 1 } }) {
                Image(systemName: "chevron.up")
                    .accessibilityLabel("Increase par, hole \(index + 1)")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 16)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(pars[index] < 5 ? Color.accentColor : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)

            Text("\(pars[index])")
                .font(.subheadline.weight(.semibold))
                .frame(width: 22, height: 20)
                .background(parBackground(pars[index]))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(parForeground(pars[index]))

            // DOWN = decrement
            Button(action: { if pars[index] > 3 { pars[index] -= 1 } }) {
                Image(systemName: "chevron.down")
                    .accessibilityLabel("Decrease par, hole \(index + 1)")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 16)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(pars[index] > 3 ? Color.accentColor : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func parBackground(_ par: Int) -> Color {
        switch par {
        case 3: return Color.blue.opacity(0.12)
        case 5: return Color.orange.opacity(0.12)
        default: return Color.accentColor.opacity(0.10)
        }
    }

    private func parForeground(_ par: Int) -> Color {
        switch par {
        case 3: return Color.blue
        case 5: return Color.orange
        default: return Color.accentColor
        }
    }

    // MARK: - Save

    private func save() {
        round.coursePars = pars

        if didChangeLogo {
            // Delete old logo file
            if let oldFilename = round.courseLogoFilename {
                store.deleteLogo(filename: oldFilename)
                round.courseLogoFilename = nil
            }
            // Save new logo if set
            if let newImage = logoImage {
                round.courseLogoFilename = store.saveLogo(newImage, for: round.id)
            }
        }

        store.update(round)
        onSave(round)
        dismiss()
    }
}

#Preview {
    EditRoundSheet(round: {
        var r = Round(courseName: "Pebble Beach")
        r.scores = Array(repeating: 5, count: 9) + Array(repeating: nil, count: 9)
        return r
    }(), onSave: { _ in })
    .environmentObject(RoundStore())
}
