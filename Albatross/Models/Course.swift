import Foundation

struct TeeOption: Codable, Hashable {
    var name: String        // e.g. "Gold", "Teal", "Blue", "White", "Black", "Green"
    var totalYards: Int
    var rating: Double?
    var slope: Int?
    var gender: String?     // "Men" or "Women"
}

struct CourseHole: Codable, Hashable {
    var number: Int
    var par: Int
    var handicap: Int
    var yardage: Int
    /// Per-tee yardages keyed by tee name — e.g. ["Gold": 400, "Teal": 357]
    var teeYardages: [String: Int]?
}

struct Course: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var shortName: String?
    var city: String
    var state: String
    var address: String?
    var zip: String?
    var phone: String?
    var website: String?
    var architect: String?
    var yearBuilt: Int?
    /// USGA course rating (e.g. 74.7) — nil for courses not yet rated
    var courseRating: Double?
    /// USGA slope rating (55–155, standard scratch = 113) — nil for courses not yet rated
    var slopeRating: Int?
    var logoURL: String?
    /// true → appears in the "Suggested" section before any search query
    var isPreloaded: Bool
    var teeOptions: [TeeOption]?
    var holes: [CourseHole]

    // Sorted by hole number, always safe to index 0-17
    private var sortedHoles: [CourseHole] {
        holes.sorted { $0.number < $1.number }
    }

    var pars: [Int]       { sortedHoles.map(\.par) }
    var handicaps: [Int]  { sortedHoles.map(\.handicap) }
    var yardages: [Int]   { sortedHoles.map(\.yardage) }
    var totalPar: Int     { holes.map(\.par).reduce(0, +) }

    var locationDisplay: String { "\(city), \(state)" }
}
