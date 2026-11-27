import UIKit
import OSLog

struct GeminiAPIClient {

    // MARK: - Configuration
    // Free API key (no credit card required): https://aistudio.google.com/app/apikey
    // Free tier: 1,500 requests/day, 15 RPM
    static let apiKey = "AIzaSyDoF_-HdEoURhjCQXzEKBpIK7QHBj8Z93A"

    private let model    = "gemini-2.5-flash"
    private let maxBytes = 4_000_000

    // MARK: - Public API

    /// Sends 1 or 2 scorecard images to Gemini and returns the raw JSON string.
    func analyze(images: [UIImage]) async throws -> String {
        Log.app.info("🏌️ Starting Gemini API call with \(images.count) image(s)")
        // Build the "parts" array: one inline_data block per image, then the text prompt
        var parts: [[String: Any]] = []

        for image in images {
            guard let data = compress(image) else { continue }
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": data.base64EncodedString()
                ]
            ])
        }
        parts.append(["text": prompt])

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["temperature": 0, "maxOutputTokens": 2048]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(Self.apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            Log.app.error("🏌️ HTTP error \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body)")
            throw GeminiError.httpError(body)
        }

        // Unwrap {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}
        if let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let first      = candidates.first,
           let content    = first["content"] as? [String: Any],
           let parts      = content["parts"] as? [[String: Any]],
           let text       = parts.first?["text"] as? String {
            Log.app.info("🏌️ Gemini responded successfully (\(text.count) chars)")
            return text
        }
        Log.app.error("🏌️ Could not unwrap response: \(String(data: data, encoding: .utf8) ?? "nil")")
        throw GeminiError.unexpectedResponse
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

    private var prompt: String {
        """
        You are analyzing a photo (or photos) of a physical paper golf scorecard. \
        There may be 1 image (all 18 holes on one card) or 2 images (front 9 on one \
        side, back 9 on the other). Scores are typically handwritten in pencil.

        Extract the following and return ONLY valid JSON — no markdown, no explanation:

        {
          "courseName": "string or null",
          "pars": [18 integers, each 3–5] or null,
          "players": [
            { "name": "string", "scores": [18 values — integer 1–15 or null if illegible] }
          ]
        }

        Rules:
        - The HOLE row (1,2,3…18) and HANDICAP/INDEX row are NOT scores — skip them.
        - The PAR row contains values like 3,4,5 — read those values into the "pars" array.
        - "OUT" = front-9 total, "IN" = back-9 total, "TOT" = grand total — skip these columns.
        - If a player name is unclear, use "Player 1", "Player 2", etc.
        - If you are not fully confident about a score value, use null — do not guess.
        - Players whose scores are entirely null should be omitted.
        - Return ONLY the JSON object, starting with { and ending with }.
        """
    }

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case badURL
        case httpError(String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .badURL:              return "Invalid Gemini API URL"
            case .httpError(let b):    return "Gemini API error: \(b)"
            case .unexpectedResponse:  return "Unexpected response from Gemini API"
            }
        }
    }
}
