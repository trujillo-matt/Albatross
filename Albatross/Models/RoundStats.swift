import Foundation

/// What a player's finished rounds add up to. Only completed 18-hole rounds count,
/// so a round abandoned after a few holes never drags an average down.
struct RoundStats {
    /// Completed 18-hole rounds, oldest first.
    let rounds: [Round]

    init(rounds all: [Round]) {
        rounds = all
            .filter { $0.status == .completed && $0.holesPlayed == 18 }
            .sorted { $0.date < $1.date }
    }

    var isEmpty: Bool { rounds.isEmpty }
    var count: Int { rounds.count }

    // MARK: Scoring

    var averageScore: Double? { average(rounds.map { Double($0.totalScore) }) }
    var bestRound: Round? { rounds.min { $0.totalScore < $1.totalScore } }

    /// The rounds drawn in the trend chart: the most recent twenty.
    var recent: [Round] { Array(rounds.suffix(20)) }

    /// Average of the latest five against the five before them. Negative is better golf.
    var recentChange: Double? {
        guard rounds.count >= 6 else { return nil }
        let latest = rounds.suffix(5).map { Double($0.totalScore) }
        let before = rounds.dropLast(5).suffix(5).map { Double($0.totalScore) }
        guard let a = average(latest), let b = average(before) else { return nil }
        return a - b
    }

    var handicap: Double? { handicapIndex(for: Array(rounds.reversed())) }

    // MARK: Holes

    enum Result: CaseIterable {
        case eagle, birdie, par, bogey, double

        var label: String {
            switch self {
            case .eagle:  return "Eagle or better"
            case .birdie: return "Birdie"
            case .par:    return "Par"
            case .bogey:  return "Bogey"
            case .double: return "Double or worse"
            }
        }

        static func of(score: Int, par: Int) -> Result {
            switch score - par {
            case ...(-2): return .eagle
            case -1:      return .birdie
            case 0:       return .par
            case 1:       return .bogey
            default:      return .double
            }
        }

        /// The difference to par that stands for this result, for choosing its ink.
        var difference: Int {
            switch self {
            case .eagle: return -2
            case .birdie: return -1
            case .par: return 0
            case .bogey: return 1
            case .double: return 2
            }
        }
    }

    /// Every scored hole across the rounds.
    private var holes: [(score: Int, par: Int, round: Round, number: Int)] {
        rounds.flatMap { round in
            (1...18).compactMap { number in
                round.scores[number - 1].map { ($0, round.effectivePars[number - 1], round, number) }
            }
        }
    }

    var holesPlayed: Int { holes.count }

    func distribution() -> [(result: Result, count: Int)] {
        let all = holes
        return Result.allCases.map { result in
            (result, all.filter { Result.of(score: $0.score, par: $0.par) == result }.count)
        }
    }

    /// Average strokes over par on par 3s, 4s and 5s.
    func byParType() -> [(par: Int, average: Double, holes: Int)] {
        [3, 4, 5].compactMap { par in
            let matching = holes.filter { $0.par == par }
            guard !matching.isEmpty else { return nil }
            let over = matching.map { Double($0.score - par) }
            return (par, over.reduce(0, +) / Double(over.count), matching.count)
        }
    }

    // MARK: Putting and greens

    /// Rounds that have putts for every hole, so a round with a few holes missing never skews the average.
    private var fullyPuttedRounds: [Round] { rounds.filter { $0.holesWithPutts == 18 } }

    var averagePuttsPerRound: Double? { average(fullyPuttedRounds.compactMap { $0.totalPutts }.map(Double.init)) }
    var averagePuttsPerHole: Double? { averagePuttsPerRound.map { $0 / 18 } }

    /// Share of known holes where the green was hit in regulation, 0 to 1.
    var greenInRegulationRate: Double? {
        let all = rounds.map { $0.greens() }
        let known = all.reduce(0) { $0 + $1.known }
        guard known > 0 else { return nil }
        return Double(all.reduce(0) { $0 + $1.hit }) / Double(known)
    }

    var hasPuttingData: Bool { averagePuttsPerRound != nil || greenInRegulationRate != nil }

    // MARK: Courses

    struct CourseSummary: Identifiable {
        let name: String
        let rounds: Int
        let best: Int
        let average: Double
        var id: String { name }
    }

    /// Courses ranked by how often they were played.
    func courses() -> [CourseSummary] {
        Dictionary(grouping: rounds, by: \.courseName)
            .map { name, played in
                let scores = played.map { $0.totalScore }
                return CourseSummary(
                    name: name,
                    rounds: played.count,
                    best: scores.min() ?? 0,
                    average: Double(scores.reduce(0, +)) / Double(scores.count))
            }
            .sorted { ($0.rounds, -$0.best) > ($1.rounds, -$1.best) }
    }

    // MARK: Records

    var bestFrontNine: Int? { rounds.map(\.frontNineTotal).min() }
    var bestBackNine: Int? { rounds.map(\.backNineTotal).min() }

    var mostBirdiesInARound: Int? {
        rounds.map { round in
            (1...18).filter { number in
                round.scores[number - 1].map { $0 - round.effectivePars[number - 1] <= -1 } ?? false
            }.count
        }.max()
    }

    var totalBirdiesOrBetter: Int {
        distribution().filter { $0.result == .eagle || $0.result == .birdie }.reduce(0) { $0 + $1.count }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
