import SwiftUI

struct TournamentStandingsView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @Environment(\.displayScale) private var displayScale

    let tournament: Tournament

    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false

    private var current: Tournament {
        tournamentStore.myTournaments.first(where: { $0.id == tournament.id }) ?? tournament
    }

    private var standings: TournamentStandings? {
        tournamentStore.standings(for: current)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Live score header ──────────────────────────────────────
                if let s = standings {
                    liveScoreHeader(s)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                // ── Per-matchup breakdown ──────────────────────────────────
                if !current.matchups.isEmpty {
                    sectionHeader("Match Results")
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 12)

                    ForEach(current.matchups.sorted { $0.matchupNumber < $1.matchupNumber }) { matchup in
                        matchupResultRow(matchup)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }

                // ── Share button ───────────────────────────────────────────
                Button(action: generateAndShare) {
                    Label("Share Standings", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer().frame(height: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
        .task {
            await tournamentStore.subscribeToStandings(tournamentID: current.id)
        }
        .onDisappear {
            Task { await tournamentStore.unsubscribeFromStandings() }
        }
    }

    // MARK: - Live score header

    private func liveScoreHeader(_ s: TournamentStandings) -> some View {
        VStack(spacing: 16) {
            // Team name + score
            HStack(alignment: .center) {
                VStack(spacing: 6) {
                    Text(s.teamA.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(format: "%.1f", s.pointsTeamA))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(s.leader?.id == s.teamA.id ? Color.accentColor : .primary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("vs")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("first to \(String(format: "%.1f", s.pointsToWin))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 6) {
                    Text(s.teamB.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(format: "%.1f", s.pointsTeamB))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(s.leader?.id == s.teamB.id ? Color.accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
            }

            // Progress gauge toward pointsToWin
            progressGauge(s)

            // Winner badge
            if s.isComplete, let winner = s.leader {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    Text("\(winner.name) wins!")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func progressGauge(_ s: TournamentStandings) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(height: 12)

                let totalPoints = s.pointsTeamA + s.pointsTeamB
                let maxPoints = max(s.pointsToWin * 2, totalPoints + 0.1)

                // Team A progress (from left)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * (s.pointsTeamA / maxPoints), height: 12)

                // Team B progress (from right)
                let bWidth = geo.size.width * (s.pointsTeamB / maxPoints)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue)
                    .frame(width: bWidth, height: 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 12)
    }

    // MARK: - Matchup row

    private func matchupResultRow(_ matchup: TournamentMatchup) -> some View {
        let teamAName = current.teams.first(where: { $0.id == matchup.teamAID })?.name ?? "A"
        let teamBName = current.teams.first(where: { $0.id == matchup.teamBID })?.name ?? "B"

        return HStack(spacing: 12) {
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
                HStack(spacing: 12) {
                    resultScore(
                        name: teamAName,
                        points: matchup.pointsTeamA,
                        isWinner: matchup.pointsTeamA > matchup.pointsTeamB
                    )
                    Text("–")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    resultScore(
                        name: teamBName,
                        points: matchup.pointsTeamB,
                        isWinner: matchup.pointsTeamB > matchup.pointsTeamA
                    )
                }
            } else {
                Text(matchup.status == .active ? "In Progress" : "Pending")
                    .font(.caption)
                    .foregroundStyle(matchup.status == .active ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((matchup.status == .active ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultScore(name: String, points: Double, isWinner: Bool) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", points))
                .font(.callout.weight(.semibold))
                .foregroundStyle(isWinner ? Color.accentColor : .primary)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Share card

    private func generateAndShare() {
        guard let s = standings else { return }
        let shareCard = StandingsShareCard(tournament: current, standings: s)
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = displayScale
        renderer.proposedSize = ProposedViewSize(width: 360, height: 640)
        if let uiImage = renderer.uiImage {
            shareImage = uiImage
            showShareSheet = true
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

// MARK: - Share Card (rendered off-screen for ImageRenderer)

private struct StandingsShareCard: View {
    // Explicit color — Color.accentColor does not resolve in ImageRenderer
    private let brandGreen = Color(red: 0.141, green: 0.208, blue: 0.153)

    let tournament: Tournament
    let standings: TournamentStandings

    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color(red: 0.98, green: 0.97, blue: 0.95))

            VStack(spacing: 0) {
                // Top brand strip
                Rectangle()
                    .fill(brandGreen)
                    .frame(height: 6)

                Spacer()

                // Logo + title
                VStack(spacing: 10) {
                    Image("black-browed-albatross")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)

                    Text("ALBATROSS")
                        .font(.footnote.weight(.semibold))
                        .tracking(4)
                        .foregroundStyle(brandGreen)

                    Text(tournament.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text(tournament.matchType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.top, 40)

                Spacer()

                // Score
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 8) {
                        Text(standings.teamA.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(String(format: "%.1f", standings.pointsTeamA))
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(standings.leader?.id == standings.teamA.id ? brandGreen : Color(white: 0.3))
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color(white: 0.8))
                        .frame(width: 1, height: 80)

                    VStack(spacing: 8) {
                        Text(standings.teamB.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(String(format: "%.1f", standings.pointsTeamB))
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(standings.leader?.id == standings.teamB.id ? brandGreen : Color(white: 0.3))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)

                // Points to win
                Text("First to \(String(format: "%.1f", standings.pointsToWin)) wins")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.top, 12)

                Spacer()

                // Per-match summary
                VStack(spacing: 6) {
                    ForEach(tournament.matchups.sorted { $0.matchupNumber < $1.matchupNumber }) { m in
                        let tAName = tournament.teams.first(where: { $0.id == m.teamAID })?.name ?? "A"
                        let tBName = tournament.teams.first(where: { $0.id == m.teamBID })?.name ?? "B"
                        HStack {
                            Text("Match \(m.matchupNumber)")
                                .font(.footnote)
                                .foregroundStyle(Color(white: 0.5))
                            Spacer()
                            if m.status == .complete {
                                Text("\(tAName) \(String(format: "%.1f", m.pointsTeamA)) – \(String(format: "%.1f", m.pointsTeamB)) \(tBName)")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color(white: 0.3))
                            } else {
                                Text(m.status == .active ? "In Progress" : "Pending")
                                    .font(.footnote)
                                    .foregroundStyle(Color(white: 0.6))
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 24)

                Spacer()

                // Bottom strip
                Rectangle()
                    .fill(brandGreen)
                    .frame(height: 6)
            }
        }
        .frame(width: 360, height: 640)
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
