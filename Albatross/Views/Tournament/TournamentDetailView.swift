import SwiftUI

struct TournamentDetailView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    let tournament: Tournament

    @State private var liveT: Tournament? = nil
    @State private var showInviteSearch = false
    @State private var isStartingDraft = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    private var current: Tournament { liveT ?? tournament }

    private var isCommissioner: Bool {
        authStore.currentProfile?.id == current.creatorUserID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header card ──────────────────────────────────────────
                headerCard

                // ── Status-driven body ───────────────────────────────────
                switch current.status {
                case .setup:    setupBody
                case .draft:    draftBody
                case .active:   activeBody
                case .complete: completeBody
                }

                // ── Error ────────────────────────────────────────────────
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
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isCommissioner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Tournament", systemImage: "trash")
                        }
                    } label: {
                        Label("Tournament Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteSearch) {
            InvitePlayersSheet(tournament: current)
        }
        .alert("Delete Tournament?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await tournamentStore.deleteTournament(current)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\u{201C}\(current.name)\u{201D} and all its data will be permanently deleted. This cannot be undone.")
        }
        .task {
            await refreshTournament()
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusBadge(current.status)
                Spacer()
                Text(current.matchType.displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                statItem(label: "Matches", value: "\(current.totalMatches)")
                statItem(label: "Points to Win", value: String(format: "%.1f", current.pointsToWin))
                statItem(label: "Players", value: "\(current.playerPool.filter { $0.inviteStatus == .accepted }.count)")
            }

            if !current.courses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(current.courses) { course in
                            Text("R\(course.roundNumber): \(course.courseName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }
                .clippedToHorizontalSafeArea()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: TournamentStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(status.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor(status).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Setup body

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Player Pool")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            playerPoolList

            if isCommissioner {
                VStack(spacing: 12) {
                    Button(action: { showInviteSearch = true }) {
                        Label("Invite Players", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.pressFeedback)

                    let acceptedCount = current.playerPool.filter { $0.inviteStatus == .accepted }.count
                    Button(action: startDraft) {
                        Group {
                            if isStartingDraft {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Start Draft", systemImage: "play.circle.fill")
                                    .font(.callout.weight(.medium))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(acceptedCount >= 2 ? Color.accentColor : Color(.systemFill))
                        .foregroundStyle(acceptedCount >= 2 ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.pressFeedback)
                    .disabled(acceptedCount < 2 || isStartingDraft)

                    if acceptedCount < 2 {
                        Text("Need at least 2 accepted players to start the draft.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
    }

    private var playerPoolList: some View {
        VStack(spacing: 1) {
            ForEach(current.playerPool) { player in
                playerRow(player)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func playerRow(_ player: TournamentPlayer) -> some View {
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
                    .foregroundStyle(.primary)
                if let username = player.profile?.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            inviteStatusBadge(player.inviteStatus)

            if player.isAdmin {
                Image(systemName: "star.fill")
                    .scaledFont(size: 11)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func inviteStatusBadge(_ status: InviteStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .foregroundStyle(inviteStatusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(inviteStatusColor(status).opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Draft body

    private var draftBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(destination: TournamentDraftView(tournament: current)) {
                HStack(spacing: 14) {
                    Image(systemName: "person.2.wave.2.fill")
                        .scaledFont(size: 28)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter Draft Room")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Captain voting & snake draft in progress")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.pressFeedback)
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    // MARK: - Active body

    private var activeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Standings summary
            if let standings = tournamentStore.standings(for: current) {
                standingsSummaryCard(standings)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            sectionHeader("Matchups")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ForEach(current.matchups) { matchup in
                NavigationLink(destination: TournamentMatchupView(tournament: current, matchup: matchup)) {
                    matchupRow(matchup)
                }
                .buttonStyle(.pressFeedback)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            NavigationLink(destination: TournamentStandingsView(tournament: current)) {
                Label("Full Standings", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .buttonStyle(.pressFeedback)
        }
    }

    private func standingsSummaryCard(_ standings: TournamentStandings) -> some View {
        HStack {
            VStack(spacing: 4) {
                Text(standings.teamA.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Text(String(format: "%.1f", standings.pointsTeamA))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(standings.leader?.id == standings.teamA.id ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text("vs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("to \(String(format: "%.1f", standings.pointsToWin))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text(standings.teamB.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Text(String(format: "%.1f", standings.pointsTeamB))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(standings.leader?.id == standings.teamB.id ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func matchupRow(_ matchup: TournamentMatchup) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Match \(matchup.matchupNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(matchup.matchType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if matchup.status == .complete {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.1f", matchup.pointsTeamA)) – \(String(format: "%.1f", matchup.pointsTeamB))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                matchupStatusBadge(matchup.status)
            }

            Image(systemName: "chevron.right")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func matchupStatusBadge(_ status: MatchupStatus) -> some View {
        Text(status == .active ? "In Progress" : "Pending")
            .font(.caption2)
            .foregroundStyle(status == .active ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((status == .active ? Color.green : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Complete body

    private var completeBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let standings = tournamentStore.standings(for: current) {
                standingsSummaryCard(standings)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if let winner = standings.leader {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .scaledFont(size: 28)
                                .foregroundStyle(.yellow)
                            Text("\(winner.name) wins!")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            NavigationLink(destination: TournamentStandingsView(tournament: current)) {
                Label("View Full Standings", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.pressFeedback)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .setup:    return .orange
        case .draft:    return .blue
        case .active:   return .green
        case .complete: return .secondary
        }
    }

    private func inviteStatusColor(_ status: InviteStatus) -> Color {
        switch status {
        case .pending:  return .orange
        case .accepted: return .green
        case .declined: return .red
        }
    }

    private func startDraft() {
        isStartingDraft = true
        Task {
            do {
                try await tournamentStore.startDraft(tournamentID: current.id)
                await refreshTournament()
            } catch {
                errorMessage = error.localizedDescription
            }
            isStartingDraft = false
        }
    }

    private func refreshTournament() async {
        await tournamentStore.loadMyTournaments()
        liveT = tournamentStore.myTournaments.first(where: { $0.id == tournament.id })
    }
}

// MARK: - Invite Players Sheet

private struct InvitePlayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var socialStore: SocialStore

    let tournament: Tournament

    @State private var searchQuery = ""
    @State private var invitedProfiles: [UserProfile] = []
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name or username", text: $searchQuery)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchQuery) { _, query in
                            Task { await socialStore.searchUsers(query: query) }
                        }
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            socialStore.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.pressFeedback)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                if socialStore.isSearching {
                    ProgressView().padding(.top, 40)
                    Spacer()
                } else {
                    List {
                        ForEach(socialStore.searchResults) { profile in
                            let alreadyInPool = tournament.playerPool.contains { $0.userID == profile.id }
                            let selected = invitedProfiles.contains { $0.id == profile.id }
                            Button(action: {
                                guard !alreadyInPool else { return }
                                if selected { invitedProfiles.removeAll { $0.id == profile.id } }
                                else { invitedProfiles.append(profile) }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName)
                                            .font(.subheadline.weight(.medium))
                                        if let u = profile.username {
                                            Text("@\(u)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if alreadyInPool {
                                        Text("Invited").font(.caption).foregroundStyle(.secondary)
                                    } else if selected {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.pressFeedback)
                            .disabled(alreadyInPool)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invite Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .albatrossConfirm) {
                    Button(action: sendInvites) {
                        if isSending { ProgressView() }
                        else {
                            Label("Send (\(invitedProfiles.count))", systemImage: "paperplane")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .disabled(invitedProfiles.isEmpty || isSending)
                }
            }
        }
    }

    private func sendInvites() {
        isSending = true
        Task {
            for profile in invitedProfiles {
                try? await tournamentStore.invitePlayer(tournamentID: tournament.id, userID: profile.id)
            }
            await MainActor.run {
                isSending = false
                dismiss()
            }
        }
    }
}
