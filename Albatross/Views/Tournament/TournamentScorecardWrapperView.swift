import SwiftUI

/// Creates (or reuses) a Round for the current user tied to a tournament matchup,
/// presents the booklet scorecard, then on finish records the matchup round and — if all
/// players have submitted — auto-calculates and saves the matchup result.
struct TournamentScorecardWrapperView: View {
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var courseStore: CourseStore

    let tournament: Tournament
    let matchup: TournamentMatchup
    /// Pass nil to create a new round; pass an existing round to resume it.
    let existingRound: Round?

    @State private var activeRound: Round? = nil
    @State private var finishedRound: Round? = nil
    @State private var didSetup = false
    @State private var navigateToSummary = false

    private var courseName: String {
        tournament.courses
            .first(where: { $0.roundNumber == matchup.matchupNumber })?
            .courseName ?? "Tournament Match"
    }

    var body: some View {
        Group {
            if navigateToSummary, let round = finishedRound {
                RoundSummaryView(round: round)
            } else if let round = activeRound {
                BookletView(roundID: round.id, opensNextHole: round.holesPlayed > 0) { roundID, _ in
                    // The booklet has already marked the round complete in the store.
                    guard let finished = roundStore.rounds.first(where: { $0.id == roundID }) else { return }
                    finishedRound = finished
                    Task { await handleFinish(finished) }
                }
            } else {
                ProgressView("Setting up scorecard…")
            }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            setup()
        }
    }

    // MARK: - Setup

    private func setup() {
        if let existing = existingRound {
            activeRound = existing
        } else {
            // Tournament courses are stored by name only. Match against the course catalog
            // so the scorecard gets real pars, handicaps, yardages and ratings instead of
            // the generic fallback layout. Unmatched names keep the fallback.
            let wanted = courseName.trimmingCharacters(in: .whitespaces).lowercased()
            let course = courseStore.allCourses.first {
                $0.name.lowercased() == wanted || $0.shortName?.lowercased() == wanted
            }
            let newRound = Round(
                courseName: courseName,
                courseID: course?.id,
                coursePars: course?.pars,
                courseHandicaps: course?.handicaps,
                courseYardages: course?.yardages,
                courseRating: course?.courseRating,
                slopeRating: course?.slopeRating,
                tournamentMatchupID: matchup.id
            )
            roundStore.add(newRound)
            activeRound = newRound
        }
    }

    // MARK: - Finish handling

    private func handleFinish(_ round: Round) async {
        guard let userID = authStore.currentProfile?.id else {
            navigateToSummary = true
            return
        }

        do {
            // 1. Record this round in the matchup_rounds table
            try await tournamentStore.recordMatchupRound(
                matchupID: matchup.id,
                roundID: round.id,
                userID: userID
            )

            // 2. Fetch all rounds for this matchup from the cloud
            let allRounds = await tournamentStore.fetchRoundsForMatchup(matchupID: matchup.id)
            let completedRounds = allRounds.filter { $0.status == .completed }
            let allPlayerIDs = matchup.teamAPlayerIDs + matchup.teamBPlayerIDs

            // 3. Decide whether every required card is in.
            //    Scramble: the team plays one ball, so one completed card per team is enough.
            //    Other formats: one completed card per paired player.
            let split = await splitRoundsByTeam(completedRounds)
            let isReady: Bool
            if matchup.matchType == .scramble {
                isReady = !split.teamA.isEmpty && !split.teamB.isEmpty
            } else {
                isReady = completedRounds.count >= allPlayerIDs.count
            }
            if isReady {
                try await tournamentStore.calculateAndSaveMatchupResult(
                    matchup: matchup,
                    teamARounds: split.teamA,
                    teamBRounds: split.teamB
                )
            }
        } catch {
            print("TournamentScorecardWrapper: handleFinish error — \(error)")
        }

        navigateToSummary = true
    }

    /// Uses matchup_round links to assign each round to team A or team B.
    private func splitRoundsByTeam(_ rounds: [Round]) async -> (teamA: [Round], teamB: [Round]) {
        let links = (try? await tournamentStore.loadMatchupRounds(matchupID: matchup.id)) ?? []
        var teamA: [Round] = []
        var teamB: [Round] = []
        for round in rounds {
            guard let link = links.first(where: { $0.roundID == round.id }) else { continue }
            if matchup.teamAPlayerIDs.contains(link.userID) {
                teamA.append(round)
            } else if matchup.teamBPlayerIDs.contains(link.userID) {
                teamB.append(round)
            }
        }
        return (teamA, teamB)
    }
}
