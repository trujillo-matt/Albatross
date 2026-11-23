import Foundation

enum RoundStatus: String, Codable {
    case inProgress = "in_progress"
    case completed = "completed"
}

struct Round: Identifiable, Codable {
    var id: UUID
    var courseName: String
    var date: Date
    var scores: [Int?]  // 18 elements, nil = not yet entered
    var status: RoundStatus

    // Course metadata — nil for manually-entered rounds or old saved rounds
    var courseID: String?
    var coursePars: [Int]?
    var courseHandicaps: [Int]?
    var courseYardages: [Int]?
    /// USGA course rating stored at time of play (e.g. 74.7)
    var courseRating: Double?
    /// USGA slope rating stored at time of play (55–155)
    var slopeRating: Int?
    /// Non-nil when this round was created for a tournament matchup.
    /// These rounds are excluded from the regular Scorecards list.
    var tournamentMatchupID: UUID?

    /// Filename (not full path) of a JPEG stored in Documents/courseLogos/
    /// Old saved rounds decode safely because this field is optional.
    var courseLogoFilename: String?

    /// Putts on each hole, when the player tracks them. Rounds saved before this existed decode as nil.
    /// Putts and greens stay on the device: the cloud rounds table has no columns for them yet.
    var putts: [Int?]?
    /// Green in regulation, when the player marked it. If it was not marked it is worked out from putts.
    var greens: [Bool?]?

    /// This card's own paper and ink (raw values of `PaperStock` and `AccentInk`).
    /// nil means "use the default from Settings". Local to the device, like putts.
    var paper: String?
    var ink: String?

    /// Resolved URL for the logo file, if one has been saved.
    var courseLogoURL: URL? {
        guard let filename = courseLogoFilename else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("courseLogos").appendingPathComponent(filename)
    }

    // Falls back to a standard par layout if no course was selected
    var effectivePars: [Int] {
        coursePars ?? [4, 4, 3, 4, 5, 3, 4, 4, 5,
                       4, 3, 4, 5, 4, 3, 4, 5, 4]
    }

    init(
        id: UUID = UUID(),
        courseName: String,
        date: Date = Date(),
        scores: [Int?] = Array(repeating: nil, count: 18),
        status: RoundStatus = .inProgress,
        courseID: String? = nil,
        coursePars: [Int]? = nil,
        courseHandicaps: [Int]? = nil,
        courseYardages: [Int]? = nil,
        courseRating: Double? = nil,
        slopeRating: Int? = nil,
        tournamentMatchupID: UUID? = nil,
        courseLogoFilename: String? = nil,
        putts: [Int?]? = nil,
        greens: [Bool?]? = nil,
        paper: String? = nil,
        ink: String? = nil
    ) {
        self.id = id
        self.courseName = courseName
        self.date = date
        self.scores = scores
        self.status = status
        self.courseID = courseID
        self.coursePars = coursePars
        self.courseHandicaps = courseHandicaps
        self.courseYardages = courseYardages
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.tournamentMatchupID = tournamentMatchupID
        self.courseLogoFilename = courseLogoFilename
        self.putts = putts
        self.greens = greens
        self.paper = paper
        self.ink = ink
    }

    var totalScore: Int {
        scores.compactMap { $0 }.reduce(0, +)
    }

    var frontNineTotal: Int {
        scores.prefix(9).compactMap { $0 }.reduce(0, +)
    }

    var backNineTotal: Int {
        scores.suffix(9).compactMap { $0 }.reduce(0, +)
    }

    // MARK: Putts and greens

    func putts(on hole: Int) -> Int? {
        guard let putts, putts.indices.contains(hole - 1) else { return nil }
        return putts[hole - 1]
    }

    /// Whether the green was hit in regulation: what the player marked, otherwise worked out
    /// from the score and putts (green reached in two strokes fewer than par or better).
    func greenInRegulation(on hole: Int) -> Bool? {
        if let greens, greens.indices.contains(hole - 1), let marked = greens[hole - 1] { return marked }
        guard let score = scores[hole - 1], let putts = putts(on: hole) else { return nil }
        return score - putts <= effectivePars[hole - 1] - 2
    }

    var totalPutts: Int? {
        let recorded = (1...18).compactMap { putts(on: $0) }
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }

    func puttsTotal(_ holes: ClosedRange<Int>) -> Int? {
        let recorded = holes.compactMap { putts(on: $0) }
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }

    var holesWithPutts: Int { (1...18).filter { putts(on: $0) != nil }.count }

    /// Greens hit and holes where that is known.
    func greens(_ holes: ClosedRange<Int> = 1...18) -> (hit: Int, known: Int) {
        let known = holes.compactMap { greenInRegulation(on: $0) }
        return (known.filter { $0 }.count, known.count)
    }

    mutating func setPutts(_ value: Int?, on hole: Int) {
        var array = putts ?? Array(repeating: nil, count: 18)
        array[hole - 1] = value
        putts = array
    }

    mutating func setGreen(_ value: Bool?, on hole: Int) {
        var array = greens ?? Array(repeating: nil, count: 18)
        array[hole - 1] = value
        greens = array
    }

    var holesPlayed: Int {
        scores.compactMap { $0 }.count
    }

    var isComplete: Bool {
        scores.allSatisfy { $0 != nil }
    }

    /// WHS score differential for this round.
    /// Uses proper formula when course rating + slope are available;
    /// falls back to (grossScore - par) otherwise.
    var scoreDifferential: Double? {
        guard isComplete else { return nil }
        let gross = Double(totalScore)
        let par = Double(effectivePars.reduce(0, +))
        if let rating = courseRating, let slope = slopeRating, slope > 0 {
            return (gross - rating) * 113.0 / Double(slope)
        } else {
            // Fallback: no slope adjustment, treat par as the benchmark
            return gross - par
        }
    }
}

/// USGA Handicap Index: average of the best 8 score differentials
/// from the most recent 20 completed rounds × 0.96.
/// Returns nil if fewer than 3 completed rounds are available.
func handicapIndex(for rounds: [Round]) -> Double? {
    let recent = Array(rounds
        .filter { $0.status == .completed }
        .prefix(20))
    guard recent.count >= 3 else { return nil }
    let differentials = recent.compactMap(\.scoreDifferential).sorted()
    let best8 = Array(differentials.prefix(8))
    guard !best8.isEmpty else { return nil }
    let avg = best8.reduce(0, +) / Double(best8.count)
    return (avg * 0.96 * 10).rounded() / 10
}

extension Round: Equatable {}
