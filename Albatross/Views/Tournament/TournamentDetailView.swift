import SwiftUI

struct TournamentDetailView: View {
    @Environment(TournamentStore.self) private var tournamentStore
    @Environment(AuthStore.self) private var authStore

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

    private var acceptedCount: Int {
        current.playerPool.filter { $0.inviteStatus == .accepted }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TournamentHeaderCard(
                    status: current.status,
                    formatName: current.matchType.displayName,
                    dayCount: current.dayCount,
                    matchCount: current.matchups.isEmpty ? nil : current.matchCount,
                    pointsToWin: current.pointsToWin,
                    acceptedPlayers: acceptedCount,
                    courses: current.courses)

                switch current.status {
                case .setup:
                    TournamentSetupSection(
                        players: current.playerPool,
                        captainIDs: Set(current.teams.compactMap(\.captainUserID)),
                        acceptedCount: acceptedCount,
                        isCommissioner: isCommissioner,
                        isStartingDraft: isStartingDraft,
                        onInvite: { showInviteSearch = true },
                        onStartDraft: startDraft)
                case .draft:
                    TournamentDraftLink(tournament: current)
                case .active:
                    TournamentActiveSection(tournament: current, me: authStore.currentProfile?.id)
                case .complete:
                    TournamentCompleteSection(tournament: current)
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

// MARK: - Sections
//
// Each part of the screen is its own view with only the values it draws, so a change to one part
// (a player accepting, a match going live) does not rebuild the others.

private struct TournamentHeaderCard: View {
    let status: TournamentStatus
    let formatName: String
    let dayCount: Int
    /// Nil until the matches exist.
    let matchCount: Int?
    let pointsToWin: Double
    let acceptedPlayers: Int
    let courses: [TournamentCourse]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TournamentStatusBadge(status: status)
                Spacer()
                Text(formatName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                StatItem(label: dayCount == 1 ? "Day" : "Days", value: "\(dayCount)")
                StatItem(label: "Matches", value: matchCount.map(String.init) ?? "—")
                StatItem(label: "Points to Win", value: pointsToWin.formatted(.number.precision(.fractionLength(1))))
                StatItem(label: "Players", value: "\(acceptedPlayers)")
            }

            if !courses.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(courses) { course in
                            Text("R\(course.roundNumber): \(course.courseName)")
                                .appFont(.small)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .clippedToHorizontalSafeArea()
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            Text(label)
                .appFont(.small)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TournamentStatusBadge: View {
    let status: TournamentStatus

    private var color: Color {
        switch status {
        case .setup:    .orange
        case .draft:    .blue
        case .active:   Color.accentColor
        case .complete: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.rawValue.capitalized)
                .appFont(.small, weight: .medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct TournamentSetupSection: View {
    let players: [TournamentPlayer]
    let captainIDs: Set<UUID>
    let acceptedCount: Int
    let isCommissioner: Bool
    let isStartingDraft: Bool
    var onInvite: () -> Void
    var onStartDraft: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Player Pool")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            VStack(spacing: 1) {
                ForEach(players) { player in
                    PlayerPoolRow(player: player, isCaptain: captainIDs.contains(player.userID))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)

            if isCommissioner {
                VStack(spacing: 12) {
                    Button(action: onInvite) {
                        Label("Invite players", systemImage: "person.badge.plus")
                            .appFont(.small, weight: .medium)
                            .appButton(fill: Color(uiColor: .secondarySystemGroupedBackground), foreground: Color.accentColor)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.pressFeedback)

                    Button(action: onStartDraft) {
                        Group {
                            if isStartingDraft {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Start captain vote and draft", systemImage: "play.circle.fill")
                                    .appFont(.body, weight: .medium)
                            }
                        }
                        .appButton(fill: acceptedCount >= 2 ? Color.brandGreen : Color(uiColor: .systemFill), foreground: acceptedCount >= 2 ? .white : .secondary)
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
}

private struct PlayerPoolRow: View {
    let player: TournamentPlayer
    let isCaptain: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String((player.profile?.displayName ?? "?").prefix(1)).uppercased())
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isCaptain { CaptainBadge() }
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

            InviteStatusBadge(status: player.inviteStatus)

            if player.isAdmin {
                Image(systemName: "star.fill")
                    .appFont(.small)
                    .foregroundStyle(.yellow)
            }
        }
        .appListRowPadding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private struct InviteStatusBadge: View {
    let status: InviteStatus

    private var color: Color {
        switch status {
        case .pending:  .orange
        case .accepted: Color.accentColor
        case .declined: .red
        }
    }

    var body: some View {
        Text(status.rawValue.capitalized)
            .appFont(.small)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct TournamentDraftLink: View {
    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink {
                TournamentDraftView(tournament: tournament)
            } label: {
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

                    Image(systemName: "chevron.forward")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.pressFeedback)
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }
}

private struct TournamentActiveSection: View {
    let tournament: Tournament
    let me: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !tournament.teeTimes.isEmpty {
                TeeTimeCard(tournament: tournament, me: me)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            // Lineups and captain callouts for each session
            if tournament.usesSessions {
                NavigationLink {
                    TournamentSessionsView(tournamentID: tournament.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lineups and callouts")
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                            Text(tournament.currentSession.map { "\($0.title), \($0.status.displayName)" } ?? "")
                                .appFont(.small)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .appFont(.small, weight: .semibold)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .buttonStyle(.pressFeedback)
            }

            // The board: team points and every match, each row opening its match
            TournamentLeaderboard(tournament: tournament) { matchup in
                TournamentMatchupView(tournament: tournament, matchup: matchup)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            NavigationLink {
                TournamentStandingsView(tournament: tournament)
            } label: {
                Label("Full standings", systemImage: "chart.bar.fill")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color(uiColor: .secondarySystemGroupedBackground), foreground: Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .buttonStyle(.pressFeedback)
        }
    }
}

private struct TournamentCompleteSection: View {
    @Environment(TournamentStore.self) private var tournamentStore

    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let standings = tournamentStore.standings(for: tournament) {
                StandingsSummaryCard(standings: standings)
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

            NavigationLink {
                TournamentStandingsView(tournament: tournament)
            } label: {
                Label("View full standings", systemImage: "chart.bar.fill")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color.brandGreen, foreground: .white)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.pressFeedback)
        }
    }
}

private struct StandingsSummaryCard: View {
    let standings: TournamentStandings

    var body: some View {
        HStack {
            VStack(spacing: 4) {
                Text(standings.teamA.name)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                Text(standings.pointsTeamA.formatted(.number.precision(.fractionLength(1))))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(standings.leader?.id == standings.teamA.id ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text("vs")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                Text("to \(standings.pointsToWin.formatted(.number.precision(.fractionLength(1))))")
                    .appFont(.small)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text(standings.teamB.name)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                Text(standings.pointsTeamB.formatted(.number.precision(.fractionLength(1))))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(standings.leader?.id == standings.teamB.id ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Invite Players Sheet

private struct InvitePlayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TournamentStore.self) private var tournamentStore
    @Environment(SocialStore.self) private var socialStore

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
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
            .background(Color(uiColor: .systemGroupedBackground))
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

    private var sessionsWithTeeTimes: [TournamentSession] {
        tournament.sortedSessions.filter { s in tournament.teeTimes.contains { $0.sessionID == s.id } }
    }

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
                        ForEach(sessionsWithTeeTimes) { s in
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
