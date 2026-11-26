import UIKit
import Supabase

/// Sends scorecard photos to the `scan-scorecard` Supabase edge function, which calls
/// Gemini with a key held server side. The app holds no Gemini key.
struct ScorecardScanClient {

    private let functionName = "scan-scorecard"
    /// Kept under the edge function's per-image limit (about 2.2 MB of JPEG).
    private let maxBytes = 2_000_000

    private struct Request: Encodable { let images: [String] }
    private struct Response: Decodable { let text: String }
    private struct ErrorBody: Decodable { let error: String }

    // MARK: - Public API

    /// Sends 1 or 2 scorecard images and returns the raw JSON string Gemini produced.
    func analyze(images: [UIImage]) async throws -> String {
        let encoded = images.compactMap { compress($0)?.base64EncodedString() }
        guard !encoded.isEmpty else { throw ScanError.noImages }

        do {
            let response: Response = try await supabase.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(body: Request(images: encoded))
            )
            return response.text
        } catch let FunctionsError.httpError(code, data) {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw ScanError.server(code: code, message: message ?? "Scanner failed.")
        } catch let error as DecodingError {
            print("🏌️ Could not decode scan response: \(error)")
            throw ScanError.unexpectedResponse
        }
    }

    // MARK: - Private

    private func compress(_ image: UIImage) -> Data? {
        // Resize so longest edge ≤ 1568 px for optimal API performance
        let maxDim: CGFloat = 1568
        // image.size is in points; the limit applies to pixels.
        let size  = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Scale 1 makes the output exactly newSize pixels, whatever the device's screen scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }

        // Reduce JPEG quality until under maxBytes
        var quality: CGFloat = 0.75
        while quality > 0.1 {
            if let d = resized.jpegData(compressionQuality: quality), d.count <= maxBytes { return d }
            quality -= 0.15
        }
        return resized.jpegData(compressionQuality: 0.1)
    }

    // MARK: - Errors

    enum ScanError: LocalizedError {
        case noImages
        case server(code: Int, message: String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .noImages:                 return "Could not read the photo."
            case .server(401, _):           return "Sign in to scan a scorecard."
            case .server(_, let message):   return message
            case .unexpectedResponse:       return "Unexpected response from the scanner."
            }
        }
    }
}
