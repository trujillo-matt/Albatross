#if DEBUG
import Foundation

/// A made-up tournament for trying the tournament screens in the simulator without a cloud account.
/// Launch the app with `-demo-tournament`. Nothing is written to the cloud: the signed-out store
/// keeps this data in memory, and scoring a match works on the local round as usual.
enum TournamentDemo {
    static let launchArgument = "-demo-tournament"

    /// The signed-in player the demo pretends to be.
    static let me = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, displayName: "Matt T")

    static let sam = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, displayName: "Sam R")
    static let alex = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, displayName: "Alex K")
    static let jordan = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!, displayName: "Jordan P")

    /// Two teams of two, an active first match that includes the player, and a second match still to be played.
    static func makeTournament() -> Tournament {
        let tournamentID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let teamAID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let teamBID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
        let now = Date()

        func player(_ profile: UserProfile, team: UUID, admin: Bool = false) -> TournamentPlayer {
            TournamentPlayer(
                id: UUID(), tournamentID: tournamentID, userID: profile.id, teamID: team,
                inviteStatus: .accepted, isAdmin: admin, draftPosition: nil, profile: profile)
        }

        func matchup(_ number: Int, status: MatchupStatus) -> TournamentMatchup {
            TournamentMatchup(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000F00\(number)")!,
                tournamentID: tournamentID, matchupNumber: number, teamAID: teamAID, teamBID: teamBID,
                teamAPlayerIDs: [me.id, sam.id], teamBPlayerIDs: [alex.id, jordan.id],
                matchType: .matchPlay, status: status, result: nil, pointsTeamA: 0, pointsTeamB: 0)
        }

        var tournament = Tournament(
            id: tournamentID, name: "Reynolds Cup", creatorUserID: me.id, status: .active,
            matchType: .matchPlay, totalMatches: 2, pointsToWin: 1.5, createdAt: now, updatedAt: now)
        tournament.courses = [
            TournamentCourse(id: UUID(), tournamentID: tournamentID, courseName: "Great Waters at Reynolds", roundNumber: 1, matchType: .matchPlay),
            TournamentCourse(id: UUID(), tournamentID: tournamentID, courseName: "Reynolds Plantation: Oconee", roundNumber: 2, matchType: .matchPlay)
        ]
        tournament.teams = [
            TournamentTeam(id: teamAID, tournamentID: tournamentID, name: "Team Matt", captainUserID: me.id),
            TournamentTeam(id: teamBID, tournamentID: tournamentID, name: "Team Alex", captainUserID: alex.id)
        ]
        tournament.playerPool = [
            player(me, team: teamAID, admin: true), player(sam, team: teamAID),
            player(alex, team: teamBID), player(jordan, team: teamBID)
        ]
        tournament.matchups = [matchup(1, status: .active), matchup(2, status: .pending)]
        return tournament
    }
}

extension SocialStore {
    /// Three friends and a recent completed round each, so the feed and the friends list have something to show.
    func installDemoFriends() {
        func finished(_ course: String, daysAgo: Int, scores: [Int]) -> Round {
            var round = Round(courseName: course, date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date())
            round.scores = scores.map { Optional($0) }
            round.status = .completed
            return round
        }
        following = [TournamentDemo.sam, TournamentDemo.alex, TournamentDemo.jordan]
        followers = [TournamentDemo.sam, TournamentDemo.alex]
        friendsFeed = [
            FeedItem(profile: TournamentDemo.sam, round: finished("Great Waters at Reynolds", daysAgo: 1,
                scores: [4, 5, 3, 4, 6, 3, 4, 5, 4, 4, 4, 3, 5, 4, 3, 4, 5, 4])),
            FeedItem(profile: TournamentDemo.alex, round: finished("Reynolds Plantation: Oconee", daysAgo: 3,
                scores: [5, 4, 4, 5, 5, 4, 3, 6, 4, 5, 3, 4, 6, 5, 4, 5, 4, 5])),
            FeedItem(profile: TournamentDemo.jordan, round: finished("Great Waters at Reynolds", daysAgo: 6,
                scores: [4, 4, 3, 5, 4, 3, 4, 4, 4, 4, 3, 4, 5, 4, 3, 4, 4, 5]))
        ]
    }
}

extension TournamentStore {
    /// Puts the demo tournament in the list. Debug builds only.
    func installDemoTournament() {
        seedForDemo([TournamentDemo.makeTournament()])
    }
}
#endif
