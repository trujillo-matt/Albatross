import UIKit

// MARK: - Result Types

struct ScorecardPlayerRow: Identifiable {
    let id: UUID = UUID()
    var label: String
    var scores: [Int?]   // Always 18 elements; nil = not detected
}

struct ScorecardParseResult {
    var courseName: String?
    var pars: [Int]?             // 18 elements when detected
    var playerRows: [ScorecardPlayerRow]
}

// MARK: - Service

struct ScorecardParserService {

    private let client = GeminiAPIClient()

    // MARK: - Public API

    /// Primary entry point — accepts 1 or 2 images (front + back of card).
    func parse(images: [UIImage]) async throws -> ScorecardParseResult {
        let jsonText = try await client.analyze(images: images)
        return decode(jsonText)
    }

    /// Convenience wrapper for single-image callers.
    func parse(image: UIImage) async throws -> ScorecardParseResult {
        try await parse(images: [image])
    }

    // MARK: - JSON Decoding

    /// Flexible score value: accepts integer, double (rounds), or any other type → nil.
    private struct FlexScore: Decodable {
        let value: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                value = nil
            } else if let i = try? c.decode(Int.self) {
                value = i
            } else if let d = try? c.decode(Double.self) {
                value = Int(d.rounded())
            } else {
                // String like "?" or any non-numeric token → treat as nil
                value = nil
            }
        }
    }

    private struct ScorecardJSON: Decodable {
        let courseName: String?
        let pars: [Int]?
        let players: [PlayerJSON]?   // optional — graceful if Gemini omits the key

        struct PlayerJSON: Decodable {
            let name: String
            let scores: [FlexScore]
        }
    }

    private func decode(_ text: String) -> ScorecardParseResult {
        // Log the raw response so you can see it in the Xcode console
        print("🏌️ Gemini raw response:\n\(text)")

        // Extract the JSON object — strip markdown fences or any preamble text.
        // Use end.lowerBound (NOT end.upperBound) to avoid a crash when `}` is
        // the very last character of the trimmed string.
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.range(of: "{"),
           let end   = cleaned.range(of: "}", options: .backwards),
           start.lowerBound <= end.lowerBound {
            cleaned = String(cleaned[start.lowerBound...end.lowerBound])
        }

        print("🏌️ Extracted JSON:\n\(cleaned)")

        guard let data    = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScorecardJSON.self, from: data)
        else {
            print("🏌️ JSON decode failed — returning empty result")
            return ScorecardParseResult(courseName: nil, pars: nil, playerRows: [])
        }

        let rows: [ScorecardPlayerRow] = (decoded.players ?? []).map { p in
            var scores = p.scores.map { $0.value }   // FlexScore → Int?
            while scores.count < 18 { scores.append(nil) }
            return ScorecardPlayerRow(label: p.name, scores: Array(scores.prefix(18)))
        }

        print("🏌️ Parsed \(rows.count) player row(s), courseName: \(decoded.courseName ?? "nil")")

        return ScorecardParseResult(
            courseName: decoded.courseName,
            pars: decoded.pars,
            playerRows: rows
        )
    }
}
