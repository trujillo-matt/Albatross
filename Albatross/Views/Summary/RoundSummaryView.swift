import SwiftUI
import Photos

struct RoundSummaryView: View {
    @State var round: Round

    @EnvironmentObject private var store: RoundStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: ShareTemplate = .minimal
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showSavedConfirmation = false
    @State private var isRendering = false
    @State private var logoImage: UIImage? = nil
    @State private var showEditRound = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    shareCardPreview
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    templateSelector
                        .padding(.horizontal, 24)

                    statsStrip
                        .padding(.horizontal, 24)

                    actionButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
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
        .overlay(savedConfirmationOverlay)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .sheet(isPresented: $showEditRound) {
            EditRoundSheet(round: round) { updated in
                round = updated
                // Reload logo in case it changed
                logoImage = loadCourseLogo(for: updated)
            }
        }
        .onAppear {
            // Load logo once — synchronous but cheap (small JPEG from disk)
            logoImage = loadCourseLogo(for: round)
        }
    }

    // MARK: - Card preview

    private var shareCardPreview: some View {
        Group {
            switch selectedTemplate {
            case .minimal:   MinimalShareCard(round: round, logoImage: logoImage)
            case .bold:      BoldShareCard(round: round, logoImage: logoImage)
            case .scorecard: ScorecardShareCard(round: round, logoImage: logoImage)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    // MARK: - Template selector

    private var templateSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style")
                .font(.custom("Baskerville", size: 14))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(ShareTemplate.allCases) { template in
                    Button(action: { selectedTemplate = template }) {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(template.previewColor)
                                .frame(height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selectedTemplate == template ? Color.accentColor : Color.clear, lineWidth: 2.5)
                                )
                                .overlay(
                                    Image(systemName: template.iconName)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(template.iconColor)
                                )
                            Text(template.label)
                                .font(.custom(selectedTemplate == template ? "Baskerville-SemiBold" : "Baskerville", size: 11))
                                .foregroundStyle(selectedTemplate == template ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statItem(label: "Front 9", value: round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—")
            Divider().frame(height: 32)
            statItem(label: "Back 9", value: round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
            Divider().frame(height: 32)
            statItem(label: "Holes", value: "\(round.holesPlayed)/18")
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.custom("Baskerville-Bold", size: 17))
            Text(label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await handleShare() } }) {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isRendering ? "Preparing…" : "Share")
                        .font(.custom("Baskerville-Bold", size: 17))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isRendering)

            Button(action: { Task { await handleSaveToPhotos() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.arrow.down")
                    Text("Save to Photos")
                        .font(.custom("Baskerville", size: 17))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemGroupedBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )
            }
            .disabled(isRendering)
        }
    }

    // MARK: - Confirmation overlay

    @ViewBuilder
    private var savedConfirmationOverlay: some View {
        if showSavedConfirmation {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("Saved to Photos")
                        .font(.custom("Baskerville-SemiBold", size: 15))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(radius: 8)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Render

    @MainActor
    private func renderCard() -> UIImage {
        let logo = logoImage
        let cardView: AnyView
        switch selectedTemplate {
        case .minimal:   cardView = AnyView(MinimalShareCard(round: round, logoImage: logo))
        case .bold:      cardView = AnyView(BoldShareCard(round: round, logoImage: logo))
        case .scorecard: cardView = AnyView(ScorecardShareCard(round: round, logoImage: logo))
        }
        let renderer = ImageRenderer(
            content: cardView
                .frame(width: 360, height: 640)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }

    // MARK: - Actions

    @MainActor
    private func handleShare() async {
        isRendering = true
        // Yield once to let the spinner appear before blocking render
        await Task.yield()
        let image = renderCard()
        isRendering = false
        shareItems = [image]
        showShareSheet = true
    }

    @MainActor
    private func handleSaveToPhotos() async {
        isRendering = true
        await Task.yield()
        let image = renderCard()
        isRendering = false

        // Check / request permission
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            guard granted else { return }
        } else {
            guard status == .authorized || status == .limited else { return }
        }

        // Save
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            withAnimation(.spring) { showSavedConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showSavedConfirmation = false }
            }
        } catch {
            print("RoundSummaryView: failed to save photo — \(error)")
        }
    }
}

// MARK: - Share Templates

enum ShareTemplate: String, CaseIterable, Identifiable {
    case minimal, bold, scorecard
    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal:   return "Minimal"
        case .bold:      return "Bold"
        case .scorecard: return "Scorecard"
        }
    }

    var previewColor: Color {
        switch self {
        case .minimal:   return Color(.systemBackground)
        case .bold:      return Color.black
        case .scorecard: return Color.accentColor.opacity(0.12)
        }
    }

    var iconName: String {
        switch self {
        case .minimal:   return "sun.min"
        case .bold:      return "bolt.fill"
        case .scorecard: return "tablecells"
        }
    }

    var iconColor: Color {
        switch self {
        case .minimal:   return .primary
        case .bold:      return .white
        case .scorecard: return .accentColor
        }
    }
}

// MARK: - Activity view controller wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        RoundSummaryView(round: {
            var r = Round(courseName: "Pebble Beach")
            r.scores = [5, 4, 4, 6, 5, 3, 4, 5, 6,
                        5, 3, 5, 6, 4, 3, 5, 6, 4]
            r.status = .completed
            return r
        }())
    }
    .environmentObject(RoundStore())
}
