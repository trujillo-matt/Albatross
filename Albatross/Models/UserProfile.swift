import Foundation

nonisolated struct UserProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var username: String?
    var avatarURL: String?
    var homeCourse: String?
    var location: String?

    // Populated when querying the profile_with_counts view
    var followersCount: Int?
    var followingCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName    = "display_name"
        case username
        case avatarURL      = "avatar_url"
        case homeCourse     = "home_course"
        case location
        case followersCount = "followers_count"
        case followingCount = "following_count"
    }

    /// URL for the locally saved avatar image (Documents/avatar.jpg)
    static var localAvatarURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("avatar.jpg")
    }
}
