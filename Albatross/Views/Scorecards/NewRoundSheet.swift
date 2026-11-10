import SwiftUI
import PhotosUI

struct NewRoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RoundStore
    @EnvironmentObject private var courseStore: CourseStore

    /// Whether the user has tapped "Enter manually" and is typing a free-form name
    @State private var isManualEntry = false
    @State private var manualCourseName: String = ""
    @FocusState private var manualFieldFocused: Bool

    /// Logo selection
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedLogoImage: UIImage? = nil

    /// Per-hole pars for manual entry (default standard layout)
    @State private var manualPars: [Int] = [4, 4, 3, 4, 5, 3, 4, 4, 5,
                                             4, 3, 4, 5, 4, 3, 4, 5, 4]

    /// Scorecard scanner state
    @State private var showScanner      = false
    @State private var isParsingImage   = false
    @State private var parseResult: ScorecardParseResult? = nil
    @State private var showScanReview   = false

    var onRoundCreated: (Round) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Logo / brand header — always visible
                    logoPicker
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    if isManualEntry {
                        manualEntrySection
                    } else {
                        // Scan option — shown above the course search list
                        Button(action: { showScanner = true }) {
                            Label("Scan Paper Scorecard", systemImage: "camera.viewfinder")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressFeedback)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                        CourseSearchView(
                            onSelect: { course in
                                startRound(
                                    courseName: course.name,
                                    courseID: course.id,
                                    coursePars: course.pars,
                                    courseHandicaps: course.handicaps,
                                    courseYardages: course.yardages,
                                    courseRating: course.courseRating,
                                    slopeRating: course.slopeRating
                                )
                            },
                            onManual: {
                                courseStore.searchText = ""
                                isManualEntry = true
                                manualFieldFocused = true
                            }
                        )
                    }
                }
                // Parsing overlay
                if isParsingImage {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Reading scorecard with AI…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationTitle("New Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        courseStore.searchText = ""
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }

                if isManualEntry {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            isManualEntry = false
                            manualCourseName = ""
                            selectedLogoImage = nil
                            selectedPhotoItem = nil
                            manualPars = [4, 4, 3, 4, 5, 3, 4, 4, 5,
                                          4, 3, 4, 5, 4, 3, 4, 5, 4]
                        }) {
                            Label("Search", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedLogoImage = image
                    }
                }
            }
            // Camera full-screen cover (avoids sheet-under-sheet issues with VNDocumentCameraViewController)
            .fullScreenCover(isPresented: $showScanner) {
                ScorecardScannerView(
                    onScanned: { images in
                        showScanner = false
                        isParsingImage = true
                        Task {
                            let parser = ScorecardParserService()
                            do {
                                parseResult = try await parser.parse(images: images)
                            } catch {
                                print("🏌️ Parse failed: \(error)")
                                // API failed — open review sheet with blank fields so user can enter manually
                                parseResult = ScorecardParseResult(courseName: nil, pars: nil, playerRows: [])
                            }
                            isParsingImage = false
                            showScanReview = true
                        }
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
            }
            // Review sheet shown after parsing completes
            .sheet(isPresented: $showScanReview) {
                if let result = parseResult {
                    ScannedScorecardReviewView(
                        result: result,
                        onConfirm: { scores, courseName in
                            showScanReview = false
                            startRound(
                                courseName: courseName,
                                courseID: nil,
                                coursePars: result.pars,
                                courseHandicaps: nil,
                                courseYardages: nil,
                                scannedScores: scores
                            )
                        },
                        onCancel: { showScanReview = false }
                    )
                }
            }
        }
    }

    // MARK: - Logo picker

    private var logoPicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                if let img = selectedLogoImage {
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

                // Camera badge
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .scaledFont(size: 11, weight: .medium)
                            .foregroundStyle(Color.accentColor)
                    )
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.pressFeedback)
    }

    // MARK: - Manual entry

    private var manualEntrySection: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Course name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Course Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    TextField("e.g. Pebble Beach", text: $manualCourseName)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .focused($manualFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { manualFieldFocused = false }
                }
                .padding(.horizontal, 20)

                // Hole pars grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hole Pars")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        parNineSection(title: "Front 9", range: 0..<9)
                        Divider().padding(.horizontal, 12)
                        parNineSection(title: "Back 9", range: 9..<18)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                }

                // Start button
                Button(action: startManualRound) {
                    Text("Start Round")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            manualCourseName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.accentColor.opacity(0.4)
                                : Color.accentColor
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(manualCourseName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Par stepper grid

    private func parNineSection(title: String, range: Range<Int>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Par \(manualPars[range].reduce(0, +))")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Hole numbers
            HStack(spacing: 0) {
                ForEach(range, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Par cells
            HStack(spacing: 4) {
                ForEach(range, id: \.self) { i in
                    parCell(index: i)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    /// One menu per hole in place of two tiny steppers: a tap opens 3, 4 or 5 under the thumb.
    private func parCell(index: Int) -> some View {
        Menu {
            Picker("Par, hole \(index + 1)", selection: $manualPars[index]) {
                ForEach(3...5, id: \.self) { par in Text("Par \(par)").tag(par) }
            }
        } label: {
            Text("\(manualPars[index])")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(parCellBackground(manualPars[index]))
                .foregroundStyle(parCellForeground(manualPars[index]))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel("Par, hole \(index + 1)")
        .accessibilityValue("\(manualPars[index])")
    }

    private func parCellBackground(_ par: Int) -> Color {
        switch par {
        case 3: return Color.secondary.opacity(0.10)
        case 5: return Color.primary.opacity(0.10)
        default: return Color.accentColor.opacity(0.08)
        }
    }

    private func parCellForeground(_ par: Int) -> Color {
        switch par {
        case 3: return Color.secondary
        case 5: return Color.primary
        default: return Color.accentColor
        }
    }

    // MARK: - Helpers

    private func startManualRound() {
        let trimmed = manualCourseName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        startRound(
            courseName: trimmed,
            courseID: nil,
            coursePars: manualPars,
            courseHandicaps: nil,
            courseYardages: nil
        )
    }

    private func startRound(
        courseName: String,
        courseID: String?,
        coursePars: [Int]?,
        courseHandicaps: [Int]?,
        courseYardages: [Int]?,
        courseRating: Double? = nil,
        slopeRating: Int? = nil,
        scannedScores: [Int?]? = nil
    ) {
        let roundID = UUID()

        // Save logo to disk if one was picked
        var logoFilename: String? = nil
        if let image = selectedLogoImage {
            logoFilename = store.saveLogo(image, for: roundID)
        }

        // If scanned scores are provided, use them; mark the round complete when all 18 are filled
        let scores = scannedScores ?? Array(repeating: nil, count: 18)
        let allFilled = scannedScores != nil && scores.allSatisfy { $0 != nil }

        let round = Round(
            id: roundID,
            courseName: courseName,
            scores: scores,
            status: allFilled ? .completed : .inProgress,
            courseID: courseID,
            coursePars: coursePars,
            courseHandicaps: courseHandicaps,
            courseYardages: courseYardages,
            courseRating: courseRating,
            slopeRating: slopeRating,
            courseLogoFilename: logoFilename
        )
        store.add(round)
        courseStore.searchText = ""
        onRoundCreated(round)
        dismiss()
    }
}

#Preview {
    NewRoundSheet(onRoundCreated: { _ in })
        .environmentObject(RoundStore())
        .environmentObject(CourseStore())
}
