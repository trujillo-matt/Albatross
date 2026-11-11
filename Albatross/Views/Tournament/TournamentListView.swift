import SwiftUI

struct TournamentListView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var showNewTournament = false
    @State private var tournamentToDelete: Tournament? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !tournamentStore.pendingInvites.isEmpty {
                        pendingInvitesSection
                    }

                    if let featured = featuredTournament {
                        leaderboardSection(featured)
                    }

                    if tournamentStore.myTournaments.isEmpty && tournamentStore.pendingInvites.isEmpty {
                        emptyTournamentState
                    } else if !tournamentStore.myTournaments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All tournaments")
                                .font(.title3.weight(.medium))
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
            .alert("Delete Tournament?", isPresented: $showDeleteAlert, presenting: tournamentToDelete) { t in
                Button("Delete", role: .destructive) {
                    Task { try? await tournamentStore.deleteTournament(t) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { t in
                Text("\u{201C}\(t.name)\u{201D} and all its data will be permanently deleted. This cannot be undone.")
            }
            .task {
                await tournamentStore.loadMyTournaments()
                await tournamentStore.loadPendingInvites()
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
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.accentColor)
                Text("\(tournamentStore.pendingInvites.count) pending invite\(tournamentStore.pendingInvites.count == 1 ? "" : "s")")
                    .font(.footnote)
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(tournament.matchType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task { try? await tournamentStore.declineInvite(tournamentID: tournament.id) }
                }) {
                    Text("Decline")
                        .font(.footnote)
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
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
            Text("Leaderboard")
                .font(.title3.weight(.medium))
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
                        Label("Delete Tournament", systemImage: "trash")
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
                        .font(.footnote)
                        .foregroundStyle(statusColor(tournament.status))
                }
                Text(tournament.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(tournamentSummary(tournament))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
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
            Text("No tournaments yet")
                .font(.headline)
            Text("Create one, invite friends, and score each match on a booklet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: { showNewTournament = true }) {
                Text("Create a tournament")
                    .font(.subheadline.weight(.medium))
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
