import Foundation

struct Follow: Codable {
    var followerID: UUID
    var followingID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case followerID  = "follower_id"
        case followingID = "following_id"
        case createdAt   = "created_at"
    }
}
