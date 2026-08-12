import Combine
import Foundation
import Supabase
import SwiftUI

// MARK: - Supabase row shape (snake_case to match DB columns)

private struct RoundRow: Codable {
    var id: UUID
    var userID: UUID
    var courseName: String
    var courseID: String?
    var coursePars: [Int]?
    var courseHandicaps: [Int]?
    var courseYardages: [Int]?
    var courseRating: Double?
    var slopeRating: Int?
    var matchupID: UUID?
    var courseLogoFilename: String?
    var date: Date
    var scores: [Int?]
    var status: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID              = "user_id"
        case courseName          = "course_name"
        case courseID            = "course_id"
        case coursePars          = "course_pars"
        case courseHandicaps     = "course_handicaps"
        case courseYardages      = "course_yardages"
        case courseRating        = "course_rating"
        case slopeRating         = "slope_rating"
        case matchupID           = "matchup_id"
        case courseLogoFilename  = "course_logo_filename"
        case date
        case scores
        case status
        case updatedAt           = "updated_at"
    }

    init(from round: Round, userID: UUID) {
        self.id = round.id
        self.userID = userID
        self.courseName = round.courseName
        self.courseID = round.courseID
        self.coursePars = round.coursePars
        self.courseHandicaps = round.courseHandicaps
        self.courseYardages = round.courseYardages
        self.courseRating = round.courseRating
        self.slopeRating = round.slopeRating
        self.matchupID = round.tournamentMatchupID
        self.courseLogoFilename = round.courseLogoFilename
        self.date = round.date
        self.scores = round.scores
        self.status = round.status.rawValue
        self.updatedAt = Date()
    }

    func toRound() -> Round {
        Round(
            id: id,
            courseName: courseName,
            date: date,
            scores: scores,
            status: RoundStatus(rawValue: status) ?? .inProgress,
            courseID: courseID,
            coursePars: coursePars,
            courseHandicaps: courseHandicaps,
            courseYardages: courseYardages,
            courseRating: courseRating,
            slopeRating: slopeRating,
            tournamentMatchupID: matchupID,
            courseLogoFilename: courseLogoFilename
        )
    }
}

// MARK: - RoundStore

@MainActor
final class RoundStore: ObservableObject {
    @Published private(set) var rounds: [Round] = []

    // Set by AlbatrossApp after both stores are created
    weak var authStore: AuthStore?

    private let saveURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("rounds.json")
    }()

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ round: Round) {
        rounds.insert(round, at: 0)
        save()
        Task { await syncToCloud(round) }
    }

    func update(_ round: Round) {
        guard let index = rounds.firstIndex(where: { $0.id == round.id }) else { return }
        rounds[index] = round
        save()
        Task { await syncToCloud(round) }
    }

    func delete(_ round: Round) {
        LiveActivityManager.shared.endActivityImmediately(for: round)
        if let filename = round.courseLogoFilename {
            deleteLogo(filename: filename)
        }
        rounds.removeAll { $0.id == round.id }
        save()
        Task { await deleteFromCloud(round.id) }
    }

    // MARK: - Logo file helpers

    func saveLogo(_ image: UIImage, for roundID: UUID) -> String? {
        let dir = logosDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("RoundStore: failed to create logos dir — \(error)")
            return nil
        }
        let filename = "\(roundID.uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("RoundStore: failed to write logo — \(error)")
            return nil
        }
        return filename
    }

    func deleteLogo(filename: String) {
        let url = logosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    private var logosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("courseLogos")
    }

    // MARK: - Local persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(rounds)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("RoundStore: failed to save — \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            rounds = try JSONDecoder().decode([Round].self, from: data)
        } catch {
            print("RoundStore: failed to load — \(error)")
        }
    }

    // MARK: - Cloud sync

    func syncToCloud(_ round: Round) async {
        guard let userID = authStore?.currentProfile?.id else { return }
        let row = RoundRow(from: round, userID: userID)
        do {
            try await supabase
                .from("rounds")
                .upsert(row)
                .execute()
        } catch {
            print("RoundStore: syncToCloud failed — \(error)")
        }
    }

    func deleteFromCloud(_ id: UUID) async {
        guard authStore?.isSignedIn == true else { return }
        do {
            try await supabase
                .from("rounds")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("RoundStore: deleteFromCloud failed — \(error)")
        }
    }

    func syncFromCloud() async {
        guard authStore?.isSignedIn == true,
              let userID = authStore?.currentProfile?.id else { return }
        do {
            let rows: [RoundRow] = try await supabase
                .from("rounds")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let localIDs = Set(rounds.map { $0.id })
            let newRounds = rows
                .filter { !localIDs.contains($0.id) }
                .map { $0.toRound() }

            if !newRounds.isEmpty {
                rounds.append(contentsOf: newRounds)
                rounds.sort { $0.date > $1.date }
                save()
            }
        } catch {
            print("RoundStore: syncFromCloud failed — \(error)")
        }
    }
}
