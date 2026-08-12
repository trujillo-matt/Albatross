import SwiftUI

struct TournamentListView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var showNewTournament = false
    @State private var tournamentToDelete: Tournament? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Section header ───────────────────────────────────────────
            HStack {
                Text("Tournaments")
                    .font(.custom("Baskerville-Bold", size: 18))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { showNewTournament = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // ── Pending invites ──────────────────────────────────────────
            if !tournamentStore.pendingInvites.isEmpty {
                pendingInvitesSection
                    .padding(.bottom, 12)
            }

            // ── Tournament cards ─────────────────────────────────────────
            if tournamentStore.myTournaments.isEmpty && tournamentStore.pendingInvites.isEmpty {
                emptyTournamentState
                    .padding(.bottom, 20)
            } else if !tournamentStore.myTournaments.isEmpty {
                tournamentScrollRow
                    .padding(.bottom, 20)
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
    }

    // MARK: - Pending invites

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text("\(tournamentStore.pendingInvites.count) pending invite\(tournamentStore.pendingInvites.count == 1 ? "" : "s")")
                    .font(.custom("Baskerville", size: 13))
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
                    .font(.custom("Baskerville-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                Text(tournament.matchType.displayName)
                    .font(.custom("Baskerville", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task { try? await tournamentStore.declineInvite(tournamentID: tournament.id) }
                }) {
                    Text("Decline")
                        .font(.custom("Baskerville", size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task { try? await tournamentStore.acceptInvite(tournamentID: tournament.id) }
                }) {
                    Text("Accept")
                        .font(.custom("Baskerville-SemiBold", size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Tournament scroll row

    private var tournamentScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(tournamentStore.myTournaments) { tournament in
                    NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                        tournamentCard(tournament)
                    }
                    .buttonStyle(.plain)
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
            .padding(.horizontal, 16)
        }
    }

    private func tournamentCard(_ tournament: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status banner
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(tournament.status))
                    .frame(width: 7, height: 7)
                Text(statusLabel(tournament.status))
                    .font(.custom("Baskerville", size: 11))
                    .foregroundStyle(statusColor(tournament.status))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(tournament.name)
                    .font(.custom("Baskerville-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(tournament.matchType.displayName)
                    .font(.custom("Baskerville", size: 12))
                    .foregroundStyle(.secondary)

                Text("\(tournament.totalMatches) match\(tournament.totalMatches == 1 ? "" : "es")")
                    .font(.custom("Baskerville", size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 148, height: 110)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Empty state

    private var emptyTournamentState: some View {
        Button(action: { showNewTournament = true }) {
            HStack(spacing: 10) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text("Create your first tournament")
                    .font(.custom("Baskerville", size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .setup:    return .orange
        case .draft:    return .blue
        case .active:   return .green
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
