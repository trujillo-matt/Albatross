#if DEBUG
import Foundation

/// A made-up tournament for trying the tournament screens in the simulator without a cloud account.
/// Launch the app with `-demo-tournament`. Nothing is written to the cloud: the signed-out store
/// keeps this data in memory, and scoring a match works on the local round as usual.
enum TournamentDemo {
    static let launchArgument = "-demo-tournament"
    /// A 12 against 12 tournament: twelve singles matches, the shape of a Sunday singles board.
    static let largeLaunchArgument = "-demo-tournament-12"

    /// The signed-in player the demo pretends to be.
    static let me = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, displayName: "Matt Trujillo")

    static let sam = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, displayName: "Sam Rhodes")
    static let alex = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, displayName: "Alex Kim")
    static let jordan = UserProfile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!, displayName: "Jordan Park")

    /// 24 made-up players over three days: best ball pairs, scramble pairs, then twelve singles.
    /// Day one and two are finished, day three has five finished, four live and three still to play.
    /// Matches come from the players: 12 a side makes six pairs matches or twelve singles matches.
    static func makeLargeTournament() -> Tournament {
        let tournamentID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let teamAID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let teamBID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
        let now = Date()

        func profile(_ index: Int, _ name: String) -> UserProfile {
            UserProfile(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xA000 + index))!, displayName: name)
        }
        // The player is the eighth name, so they sit in a live singles match on day three.
        let teamANames = ["Chris Hale", "Dana Ortiz", "Eli Brooks", "Frank Nolan", "Gina Pratt", "Hugo Weber",
                          "Ivy Tan", "Matt Trujillo", "Jake Moreno", "Kara Dunn", "Leo Fischer", "Sam Rhodes"]
        let teamBNames = ["Alex Kim", "Maya Lopez", "Noah Webb", "Owen Clarke", "Priya Shah", "Quinn Doyle",
                          "Rosa Vega", "Sean Okafor", "Jordan Park", "Tess Ward", "Uma Reid", "Vic Hansen"]
        let teamA = teamANames.enumerated().map { $0.element == "Matt Trujillo" ? me : profile($0.offset, $0.element) }
        let teamB = teamBNames.enumerated().map { profile(100 + $0.offset, $0.element) }

        typealias Outcome = (MatchResult, Double, Double)
        let teamAWins: Outcome = (.teamAWin, 1, 0)
        let teamBWins: Outcome = (.teamBWin, 0, 1)
        let halved: Outcome = (.tie, 0.5, 0.5)

        struct Day { let type: TournamentMatchType; let course: String; let outcomes: [Outcome?]; let live: Set<Int> }
        let plan: [Day] = [
            Day(type: .bestBall, course: "Great Waters at Reynolds",
                outcomes: [teamAWins, teamAWins, teamBWins, teamAWins, teamBWins, teamAWins], live: []),
            Day(type: .scramble, course: "Reynolds Plantation: Oconee",
                outcomes: [teamBWins, teamAWins, teamBWins, teamBWins, teamAWins, halved], live: []),
            Day(type: .matchPlay, course: "Great Waters at Reynolds",
                outcomes: [teamAWins, teamBWins, teamAWins, teamAWins, teamBWins, nil, nil, nil, nil, nil, nil, nil],
                live: [5, 6, 7, 8])
        ]

        var matchups: [TournamentMatchup] = []
        var courses: [TournamentCourse] = []
        for (dayIndex, day) in plan.enumerated() {
            courses.append(TournamentCourse(id: UUID(), tournamentID: tournamentID, courseName: day.course,
                                            roundNumber: dayIndex + 1, matchType: day.type))
            let size = day.type.playersPerSide
            for index in 0..<day.outcomes.count {
                let number = matchups.count + 1
                let sideA = Array(teamA[(index * size)..<((index + 1) * size)]).map(\.id)
                let sideB = Array(teamB[(index * size)..<((index + 1) * size)]).map(\.id)
                var status = MatchupStatus.pending
                var result: MatchResult?
                var pointsA = 0.0
                var pointsB = 0.0
                if let outcome = day.outcomes[index] {
                    status = .complete
                    (result, pointsA, pointsB) = outcome
                } else if day.live.contains(index) {
                    status = .active
                }
                matchups.append(TournamentMatchup(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xF100 + number))!,
                    tournamentID: tournamentID, matchupNumber: number, teamAID: teamAID, teamBID: teamBID,
                    teamAPlayerIDs: sideA, teamBPlayerIDs: sideB,
                    matchType: day.type, status: status, result: result, pointsTeamA: pointsA, pointsTeamB: pointsB))
            }
        }

        func player(_ profile: UserProfile, team: UUID, admin: Bool = false) -> TournamentPlayer {
            TournamentPlayer(
                id: UUID(), tournamentID: tournamentID, userID: profile.id, teamID: team,
                inviteStatus: .accepted, isAdmin: admin, draftPosition: nil, profile: profile)
        }

        var tournament = Tournament(
            id: tournamentID, name: "Reynolds Cup", creatorUserID: me.id, status: .active,
            matchType: .bestBall, totalMatches: matchups.count,
            pointsToWin: Tournament.pointsToWin(matchCount: matchups.count),
            createdAt: now, updatedAt: now)
        tournament.courses = courses
        tournament.teams = [
            TournamentTeam(id: teamAID, tournamentID: tournamentID, name: "Team Matt", captainUserID: me.id),
            TournamentTeam(id: teamBID, tournamentID: tournamentID, name: "Team Alex", captainUserID: teamB[0].id)
        ]
        tournament.playerPool = teamA.map { player($0, team: teamAID, admin: $0.id == me.id) } + teamB.map { player($0, team: teamBID) }
        tournament.matchups = matchups
        return tournament
    }

    /// Where the live matches stand, by match number.
    static func liveStatuses(for tournament: Tournament) -> [UUID: LiveMatchStatus] {
        let byNumber: [Int: LiveMatchStatus] = tournament.matchups.count > 4
            ? [18: LiveMatchStatus(holesPlayed: 9, lead: 2), 19: LiveMatchStatus(holesPlayed: 6, lead: 0),
               20: LiveMatchStatus(holesPlayed: 7, lead: -1), 21: LiveMatchStatus(holesPlayed: 4, lead: 1)]
            : [3: LiveMatchStatus(holesPlayed: 5, lead: 1)]
        return Dictionary(uniqueKeysWithValues: tournament.matchups.compactMap { matchup in
            byNumber[matchup.matchupNumber].map { (matchup.id, $0) }
        })
    }

    /// Two teams of two over two days of singles: day one finished, day two with the player's match live and one still to play.
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

        func matchup(_ number: Int, a: UserProfile, b: UserProfile, status: MatchupStatus,
                     result: MatchResult? = nil, pointsA: Double = 0, pointsB: Double = 0) -> TournamentMatchup {
            TournamentMatchup(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000F00\(number)")!,
                tournamentID: tournamentID, matchupNumber: number, teamAID: teamAID, teamBID: teamBID,
                teamAPlayerIDs: [a.id], teamBPlayerIDs: [b.id],
                matchType: .matchPlay, status: status, result: result, pointsTeamA: pointsA, pointsTeamB: pointsB)
        }

        var tournament = Tournament(
            id: tournamentID, name: "Reynolds Cup", creatorUserID: me.id, status: .active,
            matchType: .matchPlay, totalMatches: 4, pointsToWin: 2.5, createdAt: now, updatedAt: now)
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
        tournament.matchups = [
            matchup(1, a: me, b: alex, status: .complete, result: .teamAWin, pointsA: 1),
            matchup(2, a: sam, b: jordan, status: .complete, result: .teamBWin, pointsB: 1),
            matchup(3, a: me, b: jordan, status: .active),
            matchup(4, a: sam, b: alex, status: .pending)
        ]
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
    func installDemoTournament(large: Bool = false) {
        let tournament = large ? TournamentDemo.makeLargeTournament() : TournamentDemo.makeTournament()
        seedForDemo([tournament])
        seedLiveForDemo(TournamentDemo.liveStatuses(for: tournament))
    }
}
#endif
