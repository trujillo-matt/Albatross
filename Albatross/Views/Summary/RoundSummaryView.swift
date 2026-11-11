import SwiftUI
import Photos

/// A finished round, ready to share: a preview of the image, a choice of style, the numbers behind it,
/// and the two things people do with it.
struct RoundSummaryView: View {
    private let initialRound: Round

    @EnvironmentObject private var store: RoundStore
    @EnvironmentObject private var appearance: CardAppearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTemplate: ShareTemplate = .cover
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showSavedConfirmation = false
    @State private var isRendering = false
    @State private var logoImage: UIImage? = nil
    @State private var showEditRound = false
    @State private var showCardStyle = false

    init(round: Round) {
        initialRound = round
    }

    /// Always the stored round, so an edit made elsewhere shows up here.
    private var round: Round {
        store.rounds.first { $0.id == initialRound.id } ?? initialRound
    }

    private var style: ShareStyle { ShareStyle(appearance: appearance, round: round) }
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 32) {
                        preview.frame(maxWidth: 360)
                        controls.frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 24) {
                        preview
                        controls
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .readableContentWidth(isWide ? 920 : 520)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(savedConfirmationOverlay)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .sheet(isPresented: $showEditRound) {
            EditRoundSheet(round: round) { updated in
                logoImage = loadCourseLogo(for: updated)
            }
        }
        .sheet(isPresented: $showCardStyle) {
            NavigationStack {
                ScrollView { CardStyleForm(round: round).padding(20) }
                    .navigationTitle("Card Style")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .albatrossConfirm) {
                            Button { showCardStyle = false } label: { Label("Done", systemImage: "checkmark") }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        // Load the logo once: it is a small JPEG from disk.
        .onAppear { logoImage = loadCourseLogo(for: round) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showCardStyle = true } label: {
                    Label("Card Style", systemImage: "paintpalette")
                }
                Button { showEditRound = true } label: {
                    Label("Edit Round", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    store.delete(round)
                    dismiss()
                } label: {
                    Label("Delete Round", systemImage: "trash")
                }
            } label: {
                Label("Round Options", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Preview

    /// The image as it will be shared, scaled to fit. It is always drawn at the real size and scaled,
    /// so what you see is what is saved.
    private var preview: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / ShareCanvas.size.width
            card
                .frame(width: ShareCanvas.size.width, height: ShareCanvas.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(ShareCanvas.size.width / ShareCanvas.size.height, contentMode: .fit)
        .frame(maxHeight: isWide ? 520 : 400)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(selectedTemplate.label) image for \(round.courseName), \(round.totalScore)")
    }

    private var card: some View {
        ShareCardView(template: selectedTemplate, round: round, style: style, appearance: appearance, logo: logoImage)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 20) {
            templatePicker
            numbers
            actions
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ShareTemplate.allCases) { template in
                    Button { selectedTemplate = template } label: {
                        VStack(spacing: 6) {
                            Image(systemName: template.iconName)
                                .font(.title3)
                            Text(template.label)
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(selectedTemplate == template ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            selectedTemplate == template ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selectedTemplate == template ? Color.brandGreen : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.pressFeedback)
                    .accessibilityLabel(template.label)
                    .accessibilityAddTraits(selectedTemplate == template ? .isSelected : [])
                }
            }
        }
    }

    /// The figures behind the image. Putts and greens appear once the round has them.
    private var numbers: some View {
        let greens = round.greens()
        var items: [(String, String)] = [
            ("Score", "\(round.totalScore)"),
            ("To par", toParText),
            ("Out", round.frontNineTotal > 0 ? "\(round.frontNineTotal)" : "—"),
            ("In", round.backNineTotal > 0 ? "\(round.backNineTotal)" : "—")
        ]
        if appearance.tracksPuttsAndGreens {
            if let putts = round.totalPutts { items.append(("Putts", "\(putts)")) }
            if greens.known > 0 { items.append(("Greens", "\(greens.hit)/\(greens.known)")) }
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 0)], spacing: 16) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 2) {
                    Text(item.1)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var toParText: String {
        let played = zip(round.scores, round.effectivePars).reduce(0) { $0 + ($1.0 == nil ? 0 : $1.1) }
        let difference = round.totalScore - played
        if difference == 0 { return "E" }
        return difference > 0 ? "+\(difference)" : "−\(abs(difference))"
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { Task { await handleShare() } } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isRendering ? "Preparing" : "Share")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.brandGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
            }
            .disabled(isRendering)

            Button { Task { await handleSaveToPhotos() } } label: {
                Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.primary)
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
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 40)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Render

    @MainActor
    private func renderCard() -> UIImage {
        let renderer = ImageRenderer(
            content: card
                .frame(width: ShareCanvas.size.width, height: ShareCanvas.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        renderer.scale = displayScale
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

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            guard granted else { return }
        } else {
            guard status == .authorized || status == .limited else { return }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            withAnimation(.easeOut(duration: 0.25)) { showSavedConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeIn(duration: 0.25)) { showSavedConfirmation = false }
            }
        } catch {
            print("RoundSummaryView: failed to save photo — \(error)")
        }
    }
}

// MARK: - Share templates

enum ShareCanvas {
    /// The size every share image is drawn at, before the screen's scale is applied.
    static let size = CGSize(width: 360, height: 640)
}

enum ShareTemplate: String, CaseIterable, Identifiable {
    case cover, scorecard, score
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover:     return "Cover"
        case .scorecard: return "Card"
        case .score:     return "Score"
        }
    }

    var iconName: String {
        switch self {
        case .cover:     return "book.closed"
        case .scorecard: return "tablecells"
        case .score:     return "textformat.123"
        }
    }
}

/// The image for one template. Colors are passed in, so the same view renders on screen and in a file.
struct ShareCardView: View {
    let template: ShareTemplate
    let round: Round
    let style: ShareStyle
    let appearance: CardAppearance
    var logo: UIImage?

    var body: some View {
        content.environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var content: some View {
        switch template {
        case .cover:     CoverShareCard(round: round, style: style, appearance: appearance)
        case .scorecard: ScorecardShareCard(round: round, style: style, logoImage: logo)
        case .score:     ScoreShareCard(round: round, style: style, logoImage: logo)
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
    .environmentObject(CardAppearance())
}
