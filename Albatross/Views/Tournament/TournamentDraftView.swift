import SwiftUI

/// Live draft room — Phase 1: captain voting; Phase 2: snake draft.
struct TournamentDraftView: View {
    @Environment(TournamentStore.self) private var tournamentStore
    @Environment(AuthStore.self) private var authStore

    let tournament: Tournament

    @State private var liveT: Tournament? = nil
    @State private var captainsFinalized = false
    @State private var selectedNominees: [UUID] = []
    @State private var hasVoted = false
    @State private var isSubmittingVote = false
    @State private var isFinalizingCaptains = false
    @State private var isStartingTournament = false
    @State private var errorMessage: String? = nil
    @State private var tieCandidates: [UUID] = []
    @State private var tieSlots = 0
    @State private var tieSelection: [UUID] = []
    @State private var showTieSheet = false

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
    /// Captains are pre-placed on their teams, so they do not count as picks.
    private var currentPickNumber: Int {
        TournamentStore.draftPickCount(players: tournamentStore.draftPlayers, teams: teams)
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
                    CaptainVotePhase(
                        players: acceptedPlayers,
                        voteCounts: Dictionary(grouping: tournamentStore.captainVotes, by: \.nomineeUserID).mapValues(\.count),
                        voterCount: uniqueVoterCount,
                        selected: selectedNominees,
                        alreadyVoted: iAlreadyVoted,
                        isCommissioner: isCommissioner,
                        isSubmittingVote: isSubmittingVote,
                        isFinalizingCaptains: isFinalizingCaptains,
                        onToggle: toggleNominee,
                        onSubmit: submitVote,
                        onFinalize: { finalizeCaptains() })
                } else {
                    SnakeDraftPhase(
                        teamA: teamA,
                        teamB: teamB,
                        teamAPlayers: teamAPlayers,
                        teamBPlayers: teamBPlayers,
                        undrafted: undraftedPlayers,
                        isTeamATurn: isTeamATurn,
                        allDrafted: allDrafted,
                        iAmOnClock: iAmOnClock,
                        onClockTeamName: onClockTeam?.name,
                        isCommissioner: isCommissioner,
                        isStartingTournament: isStartingTournament,
                        onPick: makePick,
                        onOverride: overridePick,
                        onStart: startTournament)
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Vote and draft")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await tournamentStore.subscribeToDraftRoom(tournamentID: current.id)
            liveT = current
        }
        .onDisappear {
            Task { await tournamentStore.unsubscribeFromDraftRoom() }
        }
        .sheet(isPresented: $showTieSheet) {
            TieBreakSheet(
                candidates: tieCandidates.map { id in
                    (id: id, name: current.playerPool.first(where: { $0.userID == id })?.profile?.displayName ?? "Player")
                },
                slots: tieSlots,
                selection: $tieSelection,
                onCancel: { showTieSheet = false },
                onConfirm: {
                    showTieSheet = false
                    finalizeCaptains(tiebreakWinners: tieSelection)
                })
        }
    }

    private func toggleNominee(_ id: UUID) {
        guard !iAlreadyVoted else { return }
        if selectedNominees.contains(id) {
            selectedNominees.removeAll { $0 == id }
        } else if selectedNominees.count < 2 {
            selectedNominees.append(id)
        }
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

    private func finalizeCaptains(tiebreakWinners: [UUID]? = nil) {
        isFinalizingCaptains = true
        errorMessage = nil
        Task {
            do {
                try await tournamentStore.finalizeCaptains(
                    tournamentID: current.id,
                    tiebreakWinners: tiebreakWinners
                )
                await refreshTournament()
            } catch let TournamentError.captainTie(candidates, slots) {
                tieCandidates = candidates
                tieSlots = slots
                tieSelection = []
                showTieSheet = true
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

// MARK: - Sections
//
// Each part of the room is its own view with only the values it draws, so a vote arriving does not
// rebuild the draft board, and a pick does not rebuild the ballot.

private struct DraftPhaseBanner: View {
    let phase: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phase)
                .appFont(.small)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            Text(title)
                .appFont(.large, weight: .semibold)
                .foregroundStyle(.primary)
            Text(subtitle)
                .appFont(.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}

private struct DraftSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .appFont(.body, weight: .semibold)
            .foregroundStyle(.primary)
    }
}

private struct PlayerInitial: View {
    let name: String?
    var fill: Color = Color.accentColor.opacity(0.15)
    var textColor: Color = Color.accentColor
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Text(String((name ?? "?").prefix(1)).uppercased())
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(textColor)
            }
    }
}

// MARK: Phase 1: captain vote

private struct CaptainVotePhase: View {
    let players: [TournamentPlayer]
    let voteCounts: [UUID: Int]
    let voterCount: Int
    let selected: [UUID]
    let alreadyVoted: Bool
    let isCommissioner: Bool
    let isSubmittingVote: Bool
    let isFinalizingCaptains: Bool
    var onToggle: (UUID) -> Void
    var onSubmit: () -> Void
    var onFinalize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DraftPhaseBanner(
                phase: "Phase 1",
                title: "Vote for captains",
                subtitle: "Choose 2 nominees. Top 2 vote-getters become team captains."
            )

            // Vote tally
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .appFont(.small)
                    .foregroundStyle(Color.accentColor)
                Text("\(voterCount) of \(players.count) players voted")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            DraftSectionHeader(title: "Select up to 2 nominees")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ForEach(players) { player in
                NomineeRow(
                    player: player,
                    isSelected: selected.contains(player.userID),
                    // Live counts are hidden from voters until they have voted, so early
                    // results do not sway the ballot. The commissioner always sees them.
                    voteCount: (isCommissioner || alreadyVoted) ? (voteCounts[player.userID] ?? 0) : 0,
                    isLocked: alreadyVoted,
                    onTap: { onToggle(player.userID) })
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            if !alreadyVoted {
                Button(action: onSubmit) {
                    Group {
                        if isSubmittingVote {
                            ProgressView().tint(.white)
                        } else {
                            Text("Submit votes (\(selected.count)/2)")
                                .appFont(.body, weight: .medium)
                        }
                    }
                    .appButton(fill: selected.count == 2 ? Color.brandGreen : Color(uiColor: .systemFill), foreground: selected.count == 2 ? .white : .secondary)
                }
                .buttonStyle(.pressFeedback)
                .disabled(selected.count < 2 || isSubmittingVote)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Your vote is in")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            if isCommissioner {
                VStack(spacing: 8) {
                    Divider().padding(.top, 20)

                    Text("Admin actions")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Button(action: onFinalize) {
                        Group {
                            if isFinalizingCaptains {
                                ProgressView().tint(.white)
                            } else {
                                Text("Finalize captains")
                                    .appFont(.small, weight: .medium)
                            }
                        }
                        .appButton(fill: Color.accentColor.opacity(0.15), foreground: Color.accentColor)
                    }
                    .buttonStyle(.pressFeedback)
                    .disabled(isFinalizingCaptains)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct NomineeRow: View {
    let player: TournamentPlayer
    let isSelected: Bool
    /// Zero hides the count.
    let voteCount: Int
    let isLocked: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: { if !isLocked { onTap() } }) {
            HStack(spacing: 12) {
                PlayerInitial(
                    name: player.profile?.displayName,
                    fill: isSelected ? Color.brandGreen : Color.accentColor.opacity(0.15),
                    textColor: isSelected ? .white : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.profile?.displayName ?? "Player")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.primary)
                    if let username = player.profile?.username {
                        Text("@\(username)")
                            .appFont(.small)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if voteCount > 0 {
                    Text("\(voteCount)")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .appListRowPadding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .buttonStyle(.pressFeedback)
        .disabled(isLocked)
    }
}

// MARK: Phase 2: snake draft

private struct SnakeDraftPhase: View {
    let teamA: TournamentTeam?
    let teamB: TournamentTeam?
    let teamAPlayers: [TournamentPlayer]
    let teamBPlayers: [TournamentPlayer]
    let undrafted: [TournamentPlayer]
    let isTeamATurn: Bool
    let allDrafted: Bool
    let iAmOnClock: Bool
    let onClockTeamName: String?
    let isCommissioner: Bool
    let isStartingTournament: Bool
    var onPick: (TournamentPlayer) -> Void
    var onOverride: (TournamentPlayer, TournamentTeam) -> Void
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DraftPhaseBanner(
                phase: "Phase 2",
                title: "Snake draft",
                subtitle: allDrafted ? "All players have been drafted!" : "Captains take turns picking their teams."
            )

            HStack(alignment: .top, spacing: 12) {
                DraftTeamColumn(team: teamA, players: teamAPlayers, isOnClock: isTeamATurn && !allDrafted)
                DraftTeamColumn(team: teamB, players: teamBPlayers, isOnClock: !isTeamATurn && !allDrafted)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            // Undrafted players — shown to the captain who is on the clock
            if !allDrafted {
                if iAmOnClock {
                    DraftSectionHeader(title: "Your pick")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                    ForEach(undrafted) { player in
                        PickRow(player: player, onTap: { onPick(player) })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("\(onClockTeamName ?? "Captain") is on the clock…")
                            .appFont(.small)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    if isCommissioner {
                        Divider().padding(.horizontal, 16)
                        Text("Admin override")
                            .appFont(.small, weight: .medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        ForEach(undrafted) { player in
                            OverridePickRow(player: player, teamA: teamA, teamB: teamB, onOverride: { onOverride(player, $0) })
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }

            // Start tournament button (all players drafted, commissioner only)
            if allDrafted && isCommissioner {
                Button(action: onStart) {
                    Group {
                        if isStartingTournament {
                            ProgressView().tint(.white)
                        } else {
                            Label("Start tournament", systemImage: "flag.fill")
                                .appFont(.body, weight: .medium)
                        }
                    }
                    .appButton(fill: Color.brandGreen, foreground: .white)
                }
                .buttonStyle(.pressFeedback)
                .disabled(isStartingTournament)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }
}

private struct PickRow: View {
    let player: TournamentPlayer
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                PlayerInitial(name: player.profile?.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.profile?.displayName ?? "Player")
                        .appFont(.small, weight: .medium)
                    if let u = player.profile?.username {
                        Text("@\(u)").appFont(.small).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .appListRowPadding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .buttonStyle(.pressFeedback)
    }
}

private struct DraftTeamColumn: View {
    let team: TournamentTeam?
    let players: [TournamentPlayer]
    let isOnClock: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(team?.name ?? "Team")
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(.primary)
                if isOnClock {
                    Circle()
                        .fill(Color.brandGreen)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 3)
                        }
                }
            }

            Divider()

            ForEach(players) { player in
                HStack(spacing: 6) {
                    PlayerInitial(name: player.profile?.displayName, size: 28)
                    if player.userID == team?.captainUserID { CaptainBadge() }
                    Text(player.profile?.displayName ?? "Player")
                        .appFont(.small)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            if players.isEmpty {
                Text("No players yet")
                    .appFont(.small)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOnClock
                ? Color.accentColor.opacity(0.06)
                : Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOnClock ? Color.accentColor.opacity(0.4) : Color(uiColor: .separator).opacity(0.3), lineWidth: isOnClock ? 1.5 : 0.5)
        }
    }
}

private struct OverridePickRow: View {
    let player: TournamentPlayer
    let teamA: TournamentTeam?
    let teamB: TournamentTeam?
    var onOverride: (TournamentTeam) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(player.profile?.displayName ?? "Player")
                .appFont(.small)
                .foregroundStyle(.primary)
            Spacer()
            if let teamA {
                teamButton(teamA, color: .brandGreen)
            }
            if let teamB {
                teamButton(teamB, color: .blue)
            }
        }
        .appListRowPadding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func teamButton(_ team: TournamentTeam, color: Color) -> some View {
        Button(action: { onOverride(team) }) {
            Text(team.name)
                .appFont(.small)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressFeedback)
    }
}

// MARK: Tie break

private struct TieBreakSheet: View {
    let candidates: [(id: UUID, name: String)]
    let slots: Int
    @Binding var selection: [UUID]
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List(candidates, id: \.id) { candidate in
                let selected = selection.contains(candidate.id)
                Button {
                    if selected { selection.removeAll { $0 == candidate.id } }
                    else if selection.count < slots { selection.append(candidate.id) }
                } label: {
                    HStack {
                        Text(candidate.name).font(.custom("Baskerville", size: 15)).foregroundStyle(.primary)
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                }
            }
            .navigationTitle("Break the tie")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text("These nominees are tied. Choose \(slots) to become captain.")
                    .font(.custom("Baskerville", size: 13))
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", action: onConfirm)
                        .disabled(selection.count != slots)
                }
            }
        }
    }
}
