import Foundation
import OSLog
import Observation
import Supabase

// MARK: - Feed Item

struct FeedItem: Identifiable {
    var id: UUID { round.id }
    var profile: UserProfile
    var round: Round
}

// MARK: - SocialStore

@MainActor
@Observable
final class SocialStore {

    // People the current user follows (with their profiles)
    var following: [UserProfile] = []
    // People who follow the current user
    var followers: [UserProfile] = []
    // Activity feed: completed rounds from followed users
    var friendsFeed: [FeedItem] = []
    // Search results
    var searchResults: [UserProfile] = []
    var isSearching = false
    var isLoadingFeed = false

    // Set by AlbatrossApp after both stores are initialised
    @ObservationIgnored weak var authStore: AuthStore?

    // MARK: - Follow state

    func isFollowing(_ userID: UUID) -> Bool {
        following.contains { $0.id == userID }
    }

    // MARK: - Load

    func loadAll() async {
        await loadFollowing()
        await loadFollowers()
        await loadFeed()
    }

    func loadFollowing() async {
        guard let me = authStore?.currentProfile?.id else { return }
        do {
            // Fetch IDs of people I follow
            let follows: [Follow] = try await supabase
                .from("follows")
                .select()
                .eq("follower_id", value: me)
                .execute()
                .value

            guard !follows.isEmpty else {
                following = []
                return
            }

            let ids = follows.map { $0.followingID.uuidString }
            let profiles: [UserProfile] = try await supabase
                .from("profile_with_counts")
                .select()
                .in("id", values: ids)
                .execute()
                .value

            following = profiles.sorted { ($0.displayName) < ($1.displayName) }
        } catch {
            Log.app.error("SocialStore: loadFollowing failed — \(error)")
        }
    }

    func loadFollowers() async {
        guard let me = authStore?.currentProfile?.id else { return }
        do {
            let follows: [Follow] = try await supabase
                .from("follows")
                .select()
                .eq("following_id", value: me)
                .execute()
                .value

            guard !follows.isEmpty else {
                followers = []
                return
            }

            let ids = follows.map { $0.followerID.uuidString }
            let profiles: [UserProfile] = try await supabase
                .from("profile_with_counts")
                .select()
                .in("id", values: ids)
                .execute()
                .value

            followers = profiles.sorted { $0.displayName < $1.displayName }
        } catch {
            Log.app.error("SocialStore: loadFollowers failed — \(error)")
        }
    }

    func loadFeed() async {
        guard let me = authStore?.currentProfile?.id else { return }
        isLoadingFeed = true
        defer { isLoadingFeed = false }

        do {
            // Fetch IDs of people I follow
            let follows: [Follow] = try await supabase
                .from("follows")
                .select()
                .eq("follower_id", value: me)
                .execute()
                .value

            guard !follows.isEmpty else {
                friendsFeed = []
                return
            }

            let ids = follows.map { $0.followingID.uuidString }

            // Fetch their completed rounds
            struct FeedRoundRow: Codable {
                var id: UUID
                var userID: UUID
                var courseName: String
                var courseID: String?
                var coursePars: [Int]?
                var courseHandicaps: [Int]?
                var courseYardages: [Int]?
                var courseLogoFilename: String?
                var date: Date
                var scores: [Int?]
                var status: String
                var updatedAt: Date
                enum CodingKeys: String, CodingKey {
                    case id
                    case userID             = "user_id"
                    case courseName         = "course_name"
                    case courseID           = "course_id"
                    case coursePars         = "course_pars"
                    case courseHandicaps    = "course_handicaps"
                    case courseYardages     = "course_yardages"
                    case courseLogoFilename = "course_logo_filename"
                    case date
                    case scores
                    case status
                    case updatedAt          = "updated_at"
                }
            }

            let rows: [FeedRoundRow] = try await supabase
                .from("rounds")
                .select()
                .in("user_id", values: ids)
                .eq("status", value: "completed")
                .order("date", ascending: false)
                .limit(50)
                .execute()
                .value

            // Build a profile lookup map
            let profiles: [UserProfile] = try await supabase
                .from("profile_with_counts")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            friendsFeed = rows.compactMap { row -> FeedItem? in
                guard let profile = profileMap[row.userID] else { return nil }
                let round = Round(
                    id: row.id,
                    courseName: row.courseName,
                    date: row.date,
                    scores: row.scores,
                    status: RoundStatus(rawValue: row.status) ?? .completed,
                    courseID: row.courseID,
                    coursePars: row.coursePars,
                    courseHandicaps: row.courseHandicaps,
                    courseYardages: row.courseYardages,
                    courseLogoFilename: row.courseLogoFilename
                )
                return FeedItem(profile: profile, round: round)
            }
        } catch {
            Log.app.error("SocialStore: loadFeed failed — \(error)")
        }
    }

    // MARK: - Follow / Unfollow

    func follow(userID: UUID) async {
        guard let me = authStore?.currentProfile?.id else { return }
        do {
            struct FollowInsert: Encodable {
                let follower_id: UUID
                let following_id: UUID
            }
            try await supabase
                .from("follows")
                .insert(FollowInsert(follower_id: me, following_id: userID))
                .execute()

            // Refresh following list + feed
            await loadFollowing()
            await loadFeed()
        } catch {
            Log.app.error("SocialStore: follow failed — \(error)")
        }
    }

    func unfollow(userID: UUID) async {
        guard let me = authStore?.currentProfile?.id else { return }
        do {
            try await supabase
                .from("follows")
                .delete()
                .eq("follower_id", value: me)
                .eq("following_id", value: userID)
                .execute()

            following.removeAll { $0.id == userID }
            friendsFeed.removeAll { $0.profile.id == userID }
        } catch {
            Log.app.error("SocialStore: unfollow failed — \(error)")
        }
    }

    // MARK: - Search

    func searchUsers(query: String) async {
        guard let me = authStore?.currentProfile?.id,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        do {
            let term = "%\(query.lowercased())%"
            let results: [UserProfile] = try await supabase
                .from("profile_with_counts")
                .select()
                .or("username.ilike.\(term),display_name.ilike.\(term)")
                .neq("id", value: me)
                .limit(20)
                .execute()
                .value
            searchResults = results
        } catch {
            Log.app.error("SocialStore: searchUsers failed — \(error)")
            searchResults = []
        }
    }

    // MARK: - Head to Head

    func loadRounds(for userID: UUID) async -> [Round] {
        struct RemoteRoundRow: Codable {
            var id: UUID
            var courseName: String
            var courseID: String?
            var coursePars: [Int]?
            var courseHandicaps: [Int]?
            var courseYardages: [Int]?
            var courseLogoFilename: String?
            var date: Date
            var scores: [Int?]
            var status: String
            enum CodingKeys: String, CodingKey {
                case id
                case courseName         = "course_name"
                case courseID           = "course_id"
                case coursePars         = "course_pars"
                case courseHandicaps    = "course_handicaps"
                case courseYardages     = "course_yardages"
                case courseLogoFilename = "course_logo_filename"
                case date, scores, status
            }
        }
        do {
            let rows: [RemoteRoundRow] = try await supabase
                .from("rounds")
                .select()
                .eq("user_id", value: userID)
                .eq("status", value: "completed")
                .order("date", ascending: false)
                .execute()
                .value
            return rows.map {
                Round(
                    id: $0.id,
                    courseName: $0.courseName,
                    date: $0.date,
                    scores: $0.scores,
                    status: RoundStatus(rawValue: $0.status) ?? .completed,
                    courseID: $0.courseID,
                    coursePars: $0.coursePars,
                    courseHandicaps: $0.courseHandicaps,
                    courseYardages: $0.courseYardages,
                    courseLogoFilename: $0.courseLogoFilename
                )
            }
        } catch {
            Log.app.error("SocialStore: loadRounds(for:) failed — \(error)")
            return []
        }
    }
}

extension FeedItem: Equatable {}
