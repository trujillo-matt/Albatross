import SwiftUI

/// Live draft room — Phase 1: captain voting; Phase 2: snake draft.
struct TournamentDraftView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    let tournament: Tournament

    @State private var liveT: Tournament? = nil
    @State private var captainsFinalized = false
    @State private var selectedNominees: [UUID] = []
    @State private var hasVoted = false
    @State private var isSubmittingVote = false
    @State private var isFinalizingCaptains = false
    @State private var isStartingTournament = false
    @State private var errorMessage: String? = nil

    private var current: Tournament { liveT ?? tournament }
    private var myUserID: UUID? { authStore.currentProfile?.id }
    private var isCommissioner: Bool { myUserID == current.creatorUserID }

    private var acceptedPlayers: [TournamentPlayer] {
        current.playerPool.filter { $0.inviteStatus == .accepted }
    }

    private var teams: [TournamentTeam] { current.teams }
    private var teamA: TournamentTeam? { teams.first }
    private var teamB: TournamentTeam? { teams.count >= 2 ? teams[1] : nil }

    /// Captains are finalized when both teams have a captainUserID set.
    private var captainsAreSet: Bool {
        teamA?.captainUserID != nil && teamB?.captainUserID != nil
    }

    // MARK: - Snake draft state

    /// Players who still need to be assigned (no teamID)
    private var undraftedPlayers: [TournamentPlayer] {
        tournamentStore.draftPlayers.filter { $0.teamID == nil && $0.inviteStatus == .accepted }
    }

    private var teamAPlayers: [TournamentPlayer] {
        tournamentStore.draftPlayers.filter { $0.teamID == teamA?.id }
    }

    private var teamBPlayers: [TournamentPlayer] {
        tournamentStore.draftPlayers.filter { $0.teamID == teamB?.id }
    }

    /// Current pick number = total players already drafted
    private var currentPickNumber: Int {
        teamAPlayers.count + teamBPlayers.count
    }

    private var isTeamATurn: Bool {
        snakeIsTeamATurn(pickNumber: currentPickNumber)
    }

    private var onClockTeam: TournamentTeam? {
        isTeamATurn ? teamA : teamB
    }

    private var iAmOnClock: Bool {
        guard let me = myUserID, let captain = onClockTeam?.captainUserID else { return false }
        return me == captain
    }

    private var allDrafted: Bool {
        undraftedPlayers.isEmpty && !acceptedPlayers.isEmpty
    }

    // MARK: - Captain vote state

    private var uniqueVoterCount: Int {
        Set(tournamentStore.captainVotes.map(\.voterUserID)).count
    }

    private var iAlreadyVoted: Bool {
        guard let me = myUserID else { return false }
        return tournamentStore.captainVotes.contains { $0.voterUserID == me }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !captainsAreSet {
                    captainVotePhase
                } else {
                    snakeDraftPhase
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer().frame(height: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Draft Room")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await tournamentStore.subscribeToDraftRoom(tournamentID: current.id)
            liveT = current
        }
        .onDisappear {
            Task { await tournamentStore.unsubscribeFromDraftRoom() }
        }
    }

    // MARK: - Phase 1: Captain Vote

    private var captainVotePhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            phaseBanner(
                phase: "Phase 1",
                title: "Vote for Captains",
                subtitle: "Choose 2 nominees. Top 2 vote-getters become team captains."
            )

            // Vote tally
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.accentColor)
                Text("\(uniqueVoterCount) of \(acceptedPlayers.count) players voted")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Player list
            sectionHeader("Select up to 2 nominees")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ForEach(acceptedPlayers) { player in
                let isSelected = selectedNominees.contains(player.userID)
                let alreadyVoted = iAlreadyVoted
                Button(action: {
                    guard !alreadyVoted else { return }
                    if isSelected {
                        selectedNominees.removeAll { $0 == player.userID }
                    } else if selectedNominees.count < 2 {
                        selectedNominees.append(player.userID)
                    }
                }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(isSelected ? Color.brandGreen : Color.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String((player.profile?.displayName ?? "?").prefix(1)).uppercased())
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.profile?.displayName ?? "Player")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if let username = player.profile?.username {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // Show vote count for this player
                        let voteCount = tournamentStore.captainVotes.filter { $0.nomineeUserID == player.userID }.count
                        if voteCount > 0 {
                            Text("\(voteCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                .buttonStyle(.pressFeedback)
                .disabled(alreadyVoted)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // Submit vote button
            if !iAlreadyVoted {
                Button(action: submitVote) {
                    Group {
                        if isSubmittingVote {
                            ProgressView().tint(.white)
                        } else {
                            Text("Submit Votes (\(selectedNominees.count)/2)")
                                .font(.callout.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedNominees.count == 2 ? Color.brandGreen : Color(.systemFill))
                    .foregroundStyle(selectedNominees.count == 2 ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressFeedback)
                .disabled(selectedNominees.count < 2 || isSubmittingVote)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Your vote has been submitted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Commissioner: finalize captains
            if isCommissioner {
                VStack(spacing: 8) {
                    Divider().padding(.top, 20)

                    Text("Commissioner Actions")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Button(action: finalizeCaptains) {
                        Group {
                            if isFinalizingCaptains {
                                ProgressView().tint(.white)
                            } else {
                                Text("Finalize Captains")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.pressFeedback)
                    .disabled(isFinalizingCaptains)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Phase 2: Snake Draft

    private var snakeDraftPhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            phaseBanner(
                phase: "Phase 2",
                title: "Snake Draft",
                subtitle: allDrafted ? "All players have been drafted!" : "Captains take turns picking their teams."
            )

            // Team columns
            HStack(alignment: .top, spacing: 12) {
                teamColumn(team: teamA, players: teamAPlayers, isOnClock: isTeamATurn && !allDrafted)
                teamColumn(team: teamB, players: teamBPlayers, isOnClock: !isTeamATurn && !allDrafted)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            // Undrafted players — shown to the captain who is on the clock
            if !allDrafted {
                if iAmOnClock {
                    sectionHeader("Your Pick")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                    ForEach(undraftedPlayers) { player in
                        Button(action: { makePick(player) }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String((player.profile?.displayName ?? "?").prefix(1)).uppercased())
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.profile?.displayName ?? "Player")
                                        .font(.subheadline.weight(.medium))
                                    if let u = player.profile?.username {
                                        Text("@\(u)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground))
                        }
                        .buttonStyle(.pressFeedback)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                } else {
                    // Waiting for other captain
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("\(onClockTeam?.name ?? "Captain") is on the clock…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Commissioner override
                    if isCommissioner {
                        Divider().padding(.horizontal, 16)
                        Text("Commissioner Override")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        ForEach(undraftedPlayers) { player in
                            overridePickRow(player)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }

            // Start tournament button (all players drafted, commissioner only)
            if allDrafted && isCommissioner {
                Button(action: startTournament) {
                    Group {
                        if isStartingTournament {
                            ProgressView().tint(.white)
                        } else {
                            Label("Start Tournament", systemImage: "flag.fill")
                                .font(.callout.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandGreen)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressFeedback)
                .disabled(isStartingTournament)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private func teamColumn(team: TournamentTeam?, players: [TournamentPlayer], isOnClock: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(team?.name ?? "Team")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if isOnClock {
                    // Pulsing green dot
                    Circle()
                        .fill(Color.brandGreen)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 3)
                        )
                }
            }

            if let captain = team?.captainUserID,
               let captainPlayer = tournamentStore.draftPlayers.first(where: { $0.userID == captain }) {
                Text("Captain: \(captainPlayer.profile?.displayName ?? "?")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(players) { player in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String((player.profile?.displayName ?? "?").prefix(1)).uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        )
                    Text(player.profile?.displayName ?? "Player")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            if players.isEmpty {
                Text("No players yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOnClock
                ? Color.accentColor.opacity(0.06)
                : Color(.secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOnClock ? Color.accentColor.opacity(0.4) : Color(.separator).opacity(0.3), lineWidth: isOnClock ? 1.5 : 0.5)
        )
    }

    private func overridePickRow(_ player: TournamentPlayer) -> some View {
        HStack(spacing: 10) {
            Text(player.profile?.displayName ?? "Player")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            if let tA = teamA {
                Button(action: { overridePick(player, to: tA) }) {
                    Text(tA.name)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.brandGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressFeedback)
            }
            if let tB = teamB {
                Button(action: { overridePick(player, to: tB) }) {
                    Text(tB.name)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Subviews

    private func phaseBanner(phase: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phase)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
    }

    // MARK: - Actions

    private func submitVote() {
        guard !selectedNominees.isEmpty else { return }
        isSubmittingVote = true
        Task {
            do {
                try await tournamentStore.submitCaptainVote(
                    tournamentID: current.id,
                    nomineeUserIDs: selectedNominees
                )
                hasVoted = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmittingVote = false
        }
    }

    private func finalizeCaptains() {
        isFinalizingCaptains = true
        Task {
            do {
                try await tournamentStore.finalizeCaptains(tournamentID: current.id)
                await refreshTournament()
            } catch {
                errorMessage = error.localizedDescription
            }
            isFinalizingCaptains = false
        }
    }

    private func makePick(_ player: TournamentPlayer) {
        guard let me = myUserID else { return }
        Task {
            do {
                try await tournamentStore.draftPick(
                    tournamentID: current.id,
                    captainUserID: me,
                    pickedPlayerID: player.userID
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func overridePick(_ player: TournamentPlayer, to team: TournamentTeam) {
        Task {
            do {
                try await tournamentStore.overrideDraftAssignment(
                    tournamentID: current.id,
                    playerID: player.userID,
                    newTeamID: team.id
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startTournament() {
        isStartingTournament = true
        Task {
            do {
                try await tournamentStore.startTournament(tournamentID: current.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isStartingTournament = false
        }
    }

    private func refreshTournament() async {
        await tournamentStore.loadMyTournaments()
        liveT = tournamentStore.myTournaments.first(where: { $0.id == tournament.id })
    }
}
