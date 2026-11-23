import SwiftUI

/// Captain (or commissioner) sets player pairings for a matchup,
/// then each player launches their scorecard from this view.
struct TournamentMatchupView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var roundStore: RoundStore

    let tournament: Tournament
    let matchup: TournamentMatchup

    @State private var liveMatchup: TournamentMatchup? = nil
    @State private var teamASelections: [UUID] = []
    @State private var teamBSelections: [UUID] = []
    @State private var isSavingPairings = false
    @State private var showScorecard = false
    @State private var errorMessage: String? = nil

    /// The freshest copy: the store's (it reloads after scorer changes), else the one we were opened with.
    private var current: TournamentMatchup {
        if let live = liveMatchup { return live }
        let fresh = tournamentStore.myTournaments
            .first(where: { $0.id == tournament.id })?
            .matchups.first(where: { $0.id == matchup.id })
        return fresh ?? matchup
    }

    private var myUserID: UUID? { authStore.currentProfile?.id }
    private var isCommissioner: Bool { myUserID == tournament.creatorUserID }

    private var teamA: TournamentTeam? { tournament.teams.first(where: { $0.id == current.teamAID }) }
    private var teamB: TournamentTeam? { tournament.teams.first(where: { $0.id == current.teamBID }) }

    private var iAmCaptainOfTeamA: Bool { myUserID == teamA?.captainUserID }
    private var iAmCaptainOfTeamB: Bool { myUserID == teamB?.captainUserID }
    // Admins edit pairings on the admin website, so only the captains see the editor here.
    private var canSetPairings: Bool { iAmCaptainOfTeamA || iAmCaptainOfTeamB }

    private var teamAPlayers: [TournamentPlayer] {
        tournament.playerPool.filter { $0.teamID == current.teamAID }
    }
    private var teamBPlayers: [TournamentPlayer] {
        tournament.playerPool.filter { $0.teamID == current.teamBID }
    }

    /// In singles, the other match of the foursome counts too: its players can keep score for everyone.
    private var iAmInFoursome: Bool {
        guard let me = myUserID else { return false }
        return current.foursome(in: tournament.matchups).contains { $0.includes(me) }
    }

    private var iAmInThisMatchup: Bool {
        guard let me = myUserID else { return false }
        return current.teamAPlayerIDs.contains(me) || current.teamBPlayerIDs.contains(me)
    }

    private var courseName: String {
        if let id = current.sessionID, let session = tournament.sessions.first(where: { $0.id == id }) {
            if let name = session.courseName, !name.isEmpty { return name }
            return tournament.courses.first(where: { $0.roundNumber == session.dayNumber })?.courseName ?? "TBD"
        }
        return tournament.courses.first(where: { $0.roundNumber == current.matchupNumber })?.courseName ?? "TBD"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Match info ───────────────────────────────────────────
                matchInfoCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // ── Pairings ─────────────────────────────────────────────
                if current.status == .pending && canSetPairings && current.sessionID == nil {
                    pairingsEditor
                } else {
                    confirmedPairings
                }

                // ── Score entry ──────────────────────────────────────────
                if current.status != .pending && current.scorerUserID != nil {
                    groupScoringSection
                        .padding(.top, 8)
                } else if current.status != .pending && iAmInThisMatchup {
                    scoreEntrySection
                        .padding(.top, 8)
                }

                if current.status == .active && isCommissioner {
                    assignScorerMenu
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // ── Result ───────────────────────────────────────────────
                if current.status == .complete {
                    resultCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                if let error = errorMessage {
                    Text(error)
                        .appFont(.small)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer().frame(height: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Match \(current.matchupNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showScorecard) {
            scorecardDestination
        }
        .onAppear {
            initSelections()
        }
    }

    // MARK: - Match info card

    private var matchInfoCard: some View {
        HStack {
            VStack(spacing: 4) {
                Text(teamA?.name ?? "Team A")
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(.primary)
                if current.status == .complete {
                    Text(String(format: "%.1f", current.pointsTeamA))
                        .font(.title.weight(.semibold))
                        .foregroundStyle(current.pointsTeamA > current.pointsTeamB ? Color.accentColor : .primary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Image(systemName: "flag.2.crossed.fill")
                    .appFont(.large)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(current.matchType.displayName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if courseName != "TBD" {
                    Text(courseName)
                        .appFont(.small)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 4) {
                Text(teamB?.name ?? "Team B")
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(.primary)
                if current.status == .complete {
                    Text(String(format: "%.1f", current.pointsTeamB))
                        .font(.title.weight(.semibold))
                        .foregroundStyle(current.pointsTeamB > current.pointsTeamA ? Color.accentColor : .primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Pairings editor

    private var pairingsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Set Pairings")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(current.matchType.playersPerSide == 1
                 ? "Pick one player per team for this match."
                 : "Pick \(current.matchType.playersPerSide) players per team for this match.")
                .appFont(.small)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Team A picker
            teamPicker(team: teamA, players: teamAPlayers,
                       selections: $teamASelections, label: teamA?.name ?? "Team A")
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Team B picker
            teamPicker(team: teamB, players: teamBPlayers,
                       selections: $teamBSelections, label: teamB?.name ?? "Team B")
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

            // Confirm button
            Button(action: savePairings) {
                Group {
                    if isSavingPairings {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm pairings")
                            .appFont(.body, weight: .medium)
                    }
                }
                .appButton(fill: canConfirmPairings ? Color.brandGreen : Color(.systemFill), foreground: canConfirmPairings ? .white : .secondary)
            }
            .buttonStyle(.pressFeedback)
            .disabled(!canConfirmPairings || isSavingPairings)
            .padding(.horizontal, 16)
        }
    }

    private func teamPicker(team: TournamentTeam?,
                            players: [TournamentPlayer],
                            selections: Binding<[UUID]>,
                            label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .appFont(.small, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(players) { player in
                let isSelected = selections.wrappedValue.contains(player.userID)
                Button(action: {
                    if isSelected {
                        selections.wrappedValue.removeAll { $0 == player.userID }
                    } else if selections.wrappedValue.count < current.matchType.playersPerSide {
                        selections.wrappedValue.append(player.userID)
                    }
                }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(isSelected ? Color.brandGreen : Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(String((player.profile?.displayName ?? "?").prefix(1)).uppercased())
                                    .appFont(.small, weight: .semibold)
                                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                            )

                        if tournament.isCaptain(player.userID) { CaptainBadge() }
                        Text(player.profile?.displayName ?? "Player")
                            .appFont(.small)
                            .foregroundStyle(.primary)

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressFeedback)
            }
        }
    }

    private var canConfirmPairings: Bool {
        !teamASelections.isEmpty && !teamBSelections.isEmpty &&
        teamASelections.count == teamBSelections.count
    }

    // MARK: - Confirmed pairings

    private var confirmedPairings: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Pairings")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 16) {
                // Team A
                playerColumn(
                    teamName: teamA?.name ?? "Team A",
                    playerIDs: current.teamAPlayerIDs,
                    players: teamAPlayers
                )

                Text("vs")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)

                // Team B
                playerColumn(
                    teamName: teamB?.name ?? "Team B",
                    playerIDs: current.teamBPlayerIDs,
                    players: teamBPlayers
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private func playerColumn(teamName: String, playerIDs: [UUID], players: [TournamentPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(teamName)
                .appFont(.small, weight: .medium)
                .foregroundStyle(.secondary)

            ForEach(playerIDs, id: \.self) { uid in
                let player = players.first(where: { $0.userID == uid })
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String((player?.profile?.displayName ?? "?").prefix(1)).uppercased())
                                .appFont(.small, weight: .semibold)
                                .foregroundStyle(Color.accentColor)
                        )
                    if tournament.isCaptain(uid) { CaptainBadge() }
                    Text(player?.profile?.displayName ?? "Player")
                        .appFont(.small)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Score entry

    private var scoreEntrySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Your Scorecard")
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, current.matchType == .scramble ? 4 : 12)

            if current.matchType == .scramble {
                Text("Scramble: your team plays one ball, so only one teammate needs to enter the team scorecard.")
                    .font(.custom("Baskerville", size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            volunteerButton

            let myRound = existingRound()
            if let round = myRound {
                // Already started — resume
                NavigationLink(destination: TournamentScorecardWrapperView(
                    tournament: tournament,
                    matchup: current,
                    existingRound: round
                )) {
                    scoreEntryButton(label: round.status == .completed ? "View Scorecard" : "Resume Scorecard",
                                     icon: round.status == .completed ? "checkmark.circle.fill" : "pencil.circle.fill",
                                     style: .secondary)
                }
                .buttonStyle(.pressFeedback)
                .padding(.horizontal, 16)
            } else {
                // New round
                NavigationLink(destination: TournamentScorecardWrapperView(
                    tournament: tournament,
                    matchup: current,
                    existingRound: nil
                )) {
                    scoreEntryButton(label: "Enter Scorecard",
                                     icon: "pencil.circle.fill",
                                     style: .primary)
                }
                .buttonStyle(.pressFeedback)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Group scoring

    private var scorerNameText: String {
        guard let id = current.scorerUserID else { return "" }
        return tournament.playerPool.first(where: { $0.userID == id })?.profile?.displayName ?? "A player"
    }

    private var groupScoringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Group scorecard")
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Text(current.scorerUserID == myUserID
                 ? "You are keeping score for everyone in your foursome."
                 : "\(scorerNameText) is keeping score for everyone in the foursome.")
                .appFont(.small)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            NavigationLink(destination: GroupScorecardView(tournament: tournament, matchup: current)) {
                scoreEntryButton(label: current.scorerUserID == myUserID ? "Open the group scorecard" : "Watch the scorecards",
                                 icon: current.scorerUserID == myUserID ? "pencil.circle.fill" : "eye.fill",
                                 style: current.scorerUserID == myUserID ? .primary : .secondary)
            }
            .buttonStyle(.pressFeedback)
            .padding(.horizontal, 16)
        }
    }

    /// Players can volunteer to keep score for the whole group. Shown above their own scorecard until someone does.
    @ViewBuilder
    private var volunteerButton: some View {
        if current.status == .active && iAmInFoursome && current.scorerUserID == nil, let me = myUserID {
            Button {
                Task { await assignScorer(me) }
            } label: {
                Label("I'll keep score for the group", systemImage: "person.3.fill")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color(.secondarySystemGroupedBackground), foreground: Color.accentColor)
            }
            .buttonStyle(.pressFeedback)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// The organizer can assign or change the scorer at any time while the match is live.
    private var assignScorerMenu: some View {
        let players = (current.teamAPlayerIDs + current.teamBPlayerIDs).compactMap { id in
            tournament.playerPool.first(where: { $0.userID == id })
        }
        return Menu {
            ForEach(players) { p in
                Button(p.profile?.displayName ?? "Player") { Task { await assignScorer(p.userID) } }
            }
            if current.scorerUserID != nil {
                Button("No group scorer (each player scores their own)", role: .destructive) {
                    Task { await assignScorer(nil) }
                }
            }
        } label: {
            Label(current.scorerUserID == nil ? "Assign a group scorer" : "Change the group scorer",
                  systemImage: "person.badge.key")
                .appFont(.small, weight: .medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    private func assignScorer(_ id: UUID?) async {
        do {
            try await tournamentStore.setScorer(matchupID: current.id, tournamentID: tournament.id, scorerID: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum ButtonStyle2 { case primary, secondary }

    private func scoreEntryButton(label: String, icon: String, style: ButtonStyle2) -> some View {
        Label(label, systemImage: icon)
            .appFont(.small, weight: .medium)
            .appButton(fill: style == .primary ? Color.brandGreen : Color(.secondarySystemGroupedBackground), foreground: style == .primary ? .white : Color.accentColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style == .primary ? .clear : Color.accentColor.opacity(0.4), lineWidth: 1)
            )
    }

    // MARK: - Result card

    private var resultCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered.2.crossed")
                .scaledFont(size: 24)
                .foregroundStyle(Color.accentColor)

            if let result = current.result {
                let winnerName: String = {
                    switch result {
                    case .teamAWin: return teamA?.name ?? "Team A"
                    case .teamBWin: return teamB?.name ?? "Team B"
                    case .tie:      return "Tie"
                    }
                }()
                Text(result == .tie ? "Match tied!" : "\(winnerName) wins!")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary)

                Text("\(String(format: "%.1f", current.pointsTeamA)) – \(String(format: "%.1f", current.pointsTeamB))")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Scorecard destination

    @ViewBuilder
    private var scorecardDestination: some View {
        let round = existingRound()
        TournamentScorecardWrapperView(
            tournament: tournament,
            matchup: current,
            existingRound: round
        )
    }

    // MARK: - Helpers

    private func initSelections() {
        teamASelections = current.teamAPlayerIDs
        teamBSelections = current.teamBPlayerIDs
    }

    private func existingRound() -> Round? {
        // RoundStore only holds the current user's rounds, so any round
        // with this matchupID belongs to the current user.
        roundStore.rounds.first(where: { $0.tournamentMatchupID == current.id })
    }

    private func savePairings() {
        isSavingPairings = true
        Task {
            do {
                try await tournamentStore.setMatchupPairings(
                    matchupID: current.id,
                    teamAPlayerIDs: teamASelections,
                    teamBPlayerIDs: teamBSelections
                )
                await MainActor.run { liveMatchup = nil }
                await tournamentStore.loadMyTournaments()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSavingPairings = false
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .appFont(.body, weight: .semibold)
            .foregroundStyle(.primary)
    }
}
