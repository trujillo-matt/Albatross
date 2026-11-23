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
                        .appFont(.small)
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
                            Label("Delete tournament", systemImage: "trash")
                        }
                    } label: {
                        Label("Tournament options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteSearch) {
            InvitePlayersSheet(tournament: current)
        }
        .alert("Delete tournament?", isPresented: $showDeleteAlert) {
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
        .task(id: current.status == .active) {
            guard current.status == .active else { return }
            while !Task.isCancelled {
                await tournamentStore.refreshLive(for: current.id)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusBadge(current.status)
                Spacer()
                Text(current.matchType.displayName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                statItem(label: current.dayCount == 1 ? "Day" : "Days", value: "\(current.dayCount)")
                statItem(label: "Matches", value: current.matchups.isEmpty ? "—" : "\(current.matchCount)")
                statItem(label: "Points to Win", value: String(format: "%.1f", current.pointsToWin))
                statItem(label: "Players", value: "\(current.playerPool.filter { $0.inviteStatus == .accepted }.count)")
            }

            if !current.courses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(current.courses) { course in
                            Text("R\(course.roundNumber): \(course.courseName)")
                                .appFont(.small)
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
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            Text(label)
                .appFont(.small)
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: TournamentStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(status.rawValue.capitalized)
                .appFont(.small, weight: .medium)
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
                        Label("Invite players", systemImage: "person.badge.plus")
                            .appFont(.small, weight: .medium)
                            .appButton(fill: Color(.secondarySystemGroupedBackground), foreground: Color.accentColor)
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
                                Label("Start captain vote and draft", systemImage: "play.circle.fill")
                                    .appFont(.body, weight: .medium)
                            }
                        }
                        .appButton(fill: acceptedCount >= 2 ? Color.brandGreen : Color(.systemFill), foreground: acceptedCount >= 2 ? .white : .secondary)
                    }
                    .buttonStyle(.pressFeedback)
                    .disabled(acceptedCount < 2 || isStartingDraft)

                    if acceptedCount < 2 {
                        Text("You need at least 2 players to start the captain vote")
                            .appFont(.small)
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
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if current.isCaptain(player.userID) { CaptainBadge() }
                    Text(player.profile?.displayName ?? "Player")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.primary)
                }
                if let username = player.profile?.username {
                    Text("@\(username)")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            inviteStatusBadge(player.inviteStatus)

            if player.isAdmin {
                Image(systemName: "star.fill")
                    .appFont(.small)
                    .foregroundStyle(.yellow)
            }
        }
        .appListRowPadding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func inviteStatusBadge(_ status: InviteStatus) -> some View {
        Text(status.rawValue.capitalized)
            .appFont(.small)
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
                        Text("Open vote and draft")
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(.primary)
                        Text("Captain vote and draft in progress")
                            .appFont(.small)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .appFont(.small, weight: .semibold)
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
            if !current.teeTimes.isEmpty {
                TeeTimeCard(tournament: current, me: authStore.currentProfile?.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            // Lineups and captain callouts for each session
            if current.usesSessions {
                NavigationLink(destination: TournamentSessionsView(tournamentID: current.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lineups and callouts")
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                            Text(current.currentSession.map { "\($0.title), \($0.status.displayName)" } ?? "")
                                .appFont(.small)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .appFont(.small, weight: .semibold)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .buttonStyle(.pressFeedback)
            }

            // The board: team points and every match, each row opening its match
            TournamentLeaderboard(tournament: current) { matchup in
                AnyView(TournamentMatchupView(tournament: current, matchup: matchup))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            NavigationLink(destination: TournamentStandingsView(tournament: current)) {
                Label("Full standings", systemImage: "chart.bar.fill")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color(.secondarySystemGroupedBackground), foreground: Color.accentColor)
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
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                Text(String(format: "%.1f", standings.pointsTeamA))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(standings.leader?.id == standings.teamA.id ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text("vs")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                Text("to \(String(format: "%.1f", standings.pointsToWin))")
                    .appFont(.small)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text(standings.teamB.name)
                    .appFont(.small, weight: .medium)
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
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(matchup.matchType.displayName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if matchup.status == .complete {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.1f", matchup.pointsTeamA)) – \(String(format: "%.1f", matchup.pointsTeamB))")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text("Complete")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }
            } else {
                matchupStatusBadge(matchup.status)
            }

            Image(systemName: "chevron.right")
                .appFont(.small, weight: .semibold)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .appListRowPadding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func matchupStatusBadge(_ status: MatchupStatus) -> some View {
        Text(status == .active ? "In Progress" : "Pending")
            .appFont(.small)
            .foregroundStyle(status == .active ? Color.accentColor : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((status == .active ? Color.brandGreen : Color.orange).opacity(0.12))
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
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            NavigationLink(destination: TournamentStandingsView(tournament: current)) {
                Label("View full standings", systemImage: "chart.bar.fill")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color.brandGreen, foreground: .white)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.pressFeedback)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .appFont(.body, weight: .semibold)
            .foregroundStyle(.primary)
    }

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .setup:    return .orange
        case .draft:    return .blue
        case .active:   return Color.accentColor
        case .complete: return .secondary
        }
    }

    private func inviteStatusColor(_ status: InviteStatus) -> Color {
        switch status {
        case .pending:  return .orange
        case .accepted: return Color.accentColor
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
    @State private var sendErrorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let sendErrorMessage {
                    Text(sendErrorMessage)
                        .appFont(.small)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name or username", text: $searchQuery)
                        .appFont(.small)
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
                                            .appFont(.small, weight: .medium)
                                        if let u = profile.username {
                                            Text("@\(u)").appFont(.small).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if alreadyInPool {
                                        Text("Invited").appFont(.small).foregroundStyle(.secondary)
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
            .navigationTitle("Invite players")
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
        sendErrorMessage = nil
        Task {
            var failedNames: [String] = []
            for profile in invitedProfiles {
                do {
                    try await tournamentStore.invitePlayer(tournamentID: tournament.id, userID: profile.id)
                } catch {
                    failedNames.append(profile.displayName)
                }
            }
            await MainActor.run {
                isSending = false
                if failedNames.isEmpty {
                    dismiss()
                } else {
                    sendErrorMessage = "Could not invite: \(failedNames.joined(separator: ", ")). Check your connection and try again."
                }
            }
        }
    }
}

/// Tee times, as a player reads them: their own first, then everyone's grouped by time.
/// An admin sets them on the website.
struct TeeTimeCard: View {
    let tournament: Tournament
    let me: UUID?

    @State private var showAll = false

    /// The session the player should look at: the one in play, else the first with tee times.
    private var session: TournamentSession? {
        let withTimes = tournament.sortedSessions.filter { s in tournament.teeTimes.contains { $0.sessionID == s.id } }
        if let current = tournament.currentSession, withTimes.contains(where: { $0.id == current.id }) { return current }
        return withTimes.first
    }

    private func teeTime(in session: TournamentSession, for user: UUID) -> Date? {
        tournament.teeTimes.first { $0.sessionID == session.id && $0.userID == user }?.teeTime
    }

    private func groups(in session: TournamentSession) -> [(time: Date, names: [String])] {
        let rows = tournament.teeTimes.filter { $0.sessionID == session.id }
        return Dictionary(grouping: rows, by: \.teeTime).sorted { $0.key < $1.key }.map { time, rows in
            let names = rows.map { row in
                tournament.playerPool.first(where: { $0.userID == row.userID })?.profile?.displayName ?? "Player"
            }
            return (time, names.sorted())
        }
    }

    private func label(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    var body: some View {
        if let session {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tee times")
                    .appFont(.large, weight: .medium)
                    .accessibilityAddTraits(.isHeader)
                if let me, let mine = teeTime(in: session, for: me) {
                    Text("Your tee time, Day \(session.dayNumber) \(session.title): \(label(mine))")
                        .appFont(.small, weight: .semibold)
                } else {
                    Text("No tee time for you yet in Day \(session.dayNumber) \(session.title)")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Everyone's tee times", isExpanded: $showAll) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tournament.sortedSessions.filter { s in tournament.teeTimes.contains { $0.sessionID == s.id } }) { s in
                            Text("Day \(s.dayNumber), \(s.title)")
                                .appFont(.small, weight: .semibold)
                                .padding(.top, 4)
                            ForEach(groups(in: s), id: \.time) { group in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(label(group.time))
                                        .appFont(.small, monospacedDigit: true)
                                        .frame(width: 96, alignment: .leading)
                                    Text(group.names.joined(separator: ", "))
                                        .appFont(.small)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .appFont(.small)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
