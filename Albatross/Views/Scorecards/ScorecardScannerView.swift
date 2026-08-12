import SwiftUI
import VisionKit

/// UIViewControllerRepresentable wrapper around VNDocumentCameraViewController.
/// Presents the document scanner camera and returns a de-warped UIImage on success.
struct ScorecardScannerView: UIViewControllerRepresentable {
    var onScanned: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: ScorecardScannerView

        init(_ parent: ScorecardScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                parent.onCancel()
                return
            }
            // Collect all scanned pages — supports front + back of booklet-style cards.
            // VisionKit handles perspective correction for each page.
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScanned(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onCancel()
        }
    }
}
