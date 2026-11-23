import SwiftUI

struct TournamentListView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var showNewTournament = false
    @State private var tournamentToDelete: Tournament? = nil
    @State private var showDeleteAlert = false

    private func reloadTournaments() async {
        await tournamentStore.loadMyTournaments()
        await tournamentStore.loadPendingInvites()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !tournamentStore.pendingInvites.isEmpty {
                        pendingInvitesSection
                    }

                    if let featured = featuredTournament {
                        leaderboardSection(featured)
                    }

                    if !tournamentStore.myTournaments.isEmpty {
                        TournamentNewsFeed()
                    }

                    if tournamentStore.myTournaments.isEmpty && tournamentStore.pendingInvites.isEmpty {
                        emptyTournamentState
                    } else if !tournamentStore.myTournaments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All tournaments")
                                .appFont(.large, weight: .medium)
                                .accessibilityAddTraits(.isHeader)
                            tournamentList
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tournaments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showNewTournament = true }) {
                        Label("New tournament", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTournament) {
                NewTournamentSheet()
            }
            .alert("Delete tournament?", isPresented: $showDeleteAlert, presenting: tournamentToDelete) { t in
                Button("Delete", role: .destructive) {
                    Task { try? await tournamentStore.deleteTournament(t) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { t in
                Text("\u{201C}\(t.name)\u{201D} and all its data will be permanently deleted. This cannot be undone.")
            }
            .task {
                await reloadTournaments()
            }
            // Tournaments made or changed elsewhere (the web app, another phone) show up on return and on pull down.
            .refreshable { await reloadTournaments() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reloadTournaments() } }
            }
            // The board stays current while it is on screen: results and scores are refreshed every few seconds.
            .task(id: featuredTournament?.id) {
                guard let id = featuredTournament?.id else { return }
                while !Task.isCancelled {
                    await tournamentStore.refreshLive(for: id)
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    // MARK: - Pending invites

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.badge.fill")
                    .appFont(.small)
                    .foregroundStyle(Color.accentColor)
                Text("\(tournamentStore.pendingInvites.count) pending invite\(tournamentStore.pendingInvites.count == 1 ? "" : "s")")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ForEach(tournamentStore.pendingInvites) { tournament in
                pendingInviteRow(tournament)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func pendingInviteRow(_ tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tournament.name)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                Text(tournament.matchType.displayName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task { try? await tournamentStore.declineInvite(tournamentID: tournament.id) }
                }) {
                    Text("Decline")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressFeedback)

                Button(action: {
                    Task { try? await tournamentStore.acceptInvite(tournamentID: tournament.id) }
                }) {
                    Text("Accept")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .appListRowPadding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Leaderboard

    /// The tournament the board shows: the one being played, otherwise the newest.
    private var featuredTournament: Tournament? {
        let withMatches = tournamentStore.myTournaments.filter { !$0.matchups.isEmpty && $0.teams.count == 2 }
        return withMatches.first { $0.status == .active } ?? withMatches.first
    }

    private func leaderboardSection(_ tournament: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standings")
                .appFont(.large, weight: .medium)
                .accessibilityAddTraits(.isHeader)
            NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                TournamentLeaderboard(tournament: tournament)
            }
            .buttonStyle(.pressFeedback)
        }
    }

    // MARK: - Tournament list

    private var tournamentList: some View {
        VStack(spacing: 12) {
            ForEach(tournamentStore.myTournaments) { tournament in
                NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                    tournamentCard(tournament)
                }
                .buttonStyle(.pressFeedback)
                .contextMenu {
                    Button(role: .destructive) {
                        tournamentToDelete = tournament
                        showDeleteAlert = true
                    } label: {
                        Label("Delete tournament", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func tournamentCard(_ tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(tournament.status))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(statusLabel(tournament.status))
                        .appFont(.small)
                        .foregroundStyle(statusColor(tournament.status))
                }
                Text(tournament.name)
                    .appFont(.large, weight: .semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(tournamentSummary(tournament))
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .appFont(.small, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyTournamentState: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconView("trophy", size: AppSpacing.listIcon)
                .foregroundStyle(Color.accentColor)
            Text("No tournaments yet")
                .appFont(.large, weight: .semibold)
            Text("Create one, invite friends, and score each match on a booklet.")
                .appFont(.small)
                .foregroundStyle(.secondary)
            Button(action: { showNewTournament = true }) {
                Text("Create a tournament")
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.brandGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.pressFeedback)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    /// "3 days · 18 matches", or just the days until the players are set and the matches known.
    private func tournamentSummary(_ tournament: Tournament) -> String {
        let days = "\(tournament.dayCount) day\(tournament.dayCount == 1 ? "" : "s")"
        guard !tournament.matchups.isEmpty else { return days }
        let matches = tournament.matchCount
        return "\(days) · \(matches) match\(matches == 1 ? "" : "es")"
    }

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .setup:    return .secondary
        case .draft:    return .orange
        case .active:   return .accentColor
        case .complete: return .secondary
        }
    }

    private func statusLabel(_ status: TournamentStatus) -> String {
        switch status {
        case .setup:    return "Setup"
        case .draft:    return "Draft"
        case .active:   return "Active"
        case .complete: return "Complete"
        }
    }
}


/// "Tournament news": birdies, changed scores and finished matches from my tournaments.
/// Refreshes while it is on screen.
struct TournamentNewsFeed: View {
    @EnvironmentObject private var tournamentStore: TournamentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tournament news")
                .appFont(.large, weight: .medium)
                .accessibilityAddTraits(.isHeader)

            if tournamentStore.news.isEmpty {
                Text("Birdies, changed scores and finished matches show up here")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(tournamentStore.news) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(item.kind == "score_change" ? Color.orange : (item.kind == "match_result" ? Color.secondary : Color.brandGreen))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.headline)
                                    .appFont(.small)
                                Text(item.createdAt.formatted(.relative(presentation: .named)))
                                    .appFont(.small)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .appListRowPadding()
                        .accessibilityElement(children: .combine)
                        if item.id != tournamentStore.news.last?.id { Divider().padding(.leading, 34) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task {
            while !Task.isCancelled {
                await tournamentStore.loadNews()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
