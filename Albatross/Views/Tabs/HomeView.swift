import SwiftUI

/// The Clubhouse: where your golf starts. The round you are in, your tournaments, then friends.
struct HomeView: View {
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var socialStore: SocialStore

    /// Opens a round's booklet on the Scorecards tab.
    var onOpenRound: (UUID) -> Void
    /// Opens the new round sheet on the Scorecards tab.
    var onNewRound: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showUserSearch = false
    @State private var selectedProfile: UserProfile? = nil

    /// Side by side normally; stacked at the largest text sizes, where the course name would break mid-word.
    private var continueLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }

    private var roundInProgress: Round? {
        roundStore.rounds
            .filter { $0.status == .inProgress && $0.tournamentMatchupID == nil }
            .max { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    continueSection

                    if !tournamentStore.myTournaments.isEmpty {
                        tournamentsSection
                    }

                    friendsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .readableContentWidth()
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await socialStore.loadFeed() }
            .navigationTitle("Clubhouse")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showUserSearch = true }) {
                        Label("Find friends", systemImage: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showUserSearch) {
                UserSearchView()
            }
            .sheet(item: $selectedProfile) { profile in
                UserProfileView(profile: profile)
            }
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .accessibilityAddTraits(.isHeader)
    }

    /// The moment on this screen: the round you are in, drawn as its booklet cover.
    @ViewBuilder
    private var continueSection: some View {
        if let round = roundInProgress {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Continue")
                continueLayout {
                    CourseCoverView(round: round)
                        .frame(height: 144)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(round.courseName)
                            .font(.headline)
                        Text(progressText(for: round))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button { onOpenRound(round.id) } label: {
                            Text("Resume round")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressFeedback)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Continue")
                VStack(alignment: .leading, spacing: 12) {
                    Text("No round in progress")
                        .font(.headline)
                    Text("Start one and it waits here until you pick it back up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(action: onNewRound) {
                        Text("Start a round")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.pressFeedback)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var tournamentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tournaments")
            VStack(spacing: 0) {
                ForEach(Array(tournamentStore.myTournaments.enumerated()), id: \.element.id) { index, tournament in
                    NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                        tournamentRow(tournament)
                    }
                    .buttonStyle(.pressFeedback)
                    if index < tournamentStore.myTournaments.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func tournamentRow(_ tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tournament.status == .active ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(tournament.matchType.displayName) · \(tournament.totalMatches) matches")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Friends")

            if socialStore.isLoadingFeed && socialStore.friendsFeed.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if socialStore.following.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Follow friends to see their rounds here")
                        .font(.headline)
                    Text("Find golfers you know and their scores show up in this feed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button { showUserSearch = true } label: {
                        Text("Find friends")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.pressFeedback)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if socialStore.friendsFeed.isEmpty {
                Text("Your friends have not posted a round yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(socialStore.friendsFeed) { item in
                        FeedItemCard(item: item) {
                            selectedProfile = item.profile
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// "3 of 18 holes · +1": holes entered and where the round stands against par so far.
    private func progressText(for round: Round) -> String {
        guard round.holesPlayed > 0 else { return "Not started" }
        let difference = zip(round.scores, round.effectivePars).reduce(0) { total, hole in
            guard let score = hole.0 else { return total }
            return total + score - hole.1
        }
        let toPar = difference == 0 ? "E" : difference > 0 ? "+\(difference)" : "\(difference)"
        return "\(round.holesPlayed) of 18 holes · \(toPar)"
    }
}

// MARK: - Feed item card

struct FeedItemCard: View {
    let item: FeedItem
    let onTapProfile: () -> Void

    private var round: Round { item.round }
    private var profile: UserProfile { item.profile }

    private var totalPar: Int { round.effectivePars.reduce(0, +) }
    private var diff: Int { round.totalScore - totalPar }

    private var initials: String {
        let parts = profile.displayName.split(separator: " ")
        return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: avatar + name + date
            HStack(spacing: 10) {
                Button(action: onTapProfile) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.pressFeedback)

                VStack(alignment: .leading, spacing: 1) {
                    Button(action: onTapProfile) {
                        Text(profile.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.pressFeedback)

                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Score badge
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(round.totalScore)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                        .font(.caption)
                        .foregroundStyle(scoreColor(diff))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Course name
            HStack {
                Image(systemName: "flag.fill")
                    .scaledFont(size: 10)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(round.courseName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Hole score strip
            holeStrip
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    private var holeStrip: some View {
        let pars = round.effectivePars
        return HStack(spacing: 3) {
            ForEach(0..<18, id: \.self) { i in
                let score = round.scores.indices.contains(i) ? round.scores[i] : nil
                let par = pars.indices.contains(i) ? pars[i] : 4
                holeCell(score: score, par: par)
            }
        }
    }

    private func holeCell(score: Int?, par: Int) -> some View {
        let bg: Color = {
            guard let s = score else { return Color(.tertiarySystemGroupedBackground) }
            let d = s - par
            return d == 0 ? Color(.tertiarySystemGroupedBackground) : BookletStyle.ink(forDifference: d)
        }()

        let fg: Color = {
            guard let s = score else { return .secondary }
            let d = s - par
            return d == 0 ? .primary : .white
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(bg)
                .frame(height: 28)
            if let s = score {
                Text("\(s)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(fg)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreColor(_ diff: Int) -> Color {
        switch diff {
        case ..<0: return BookletStyle.adaptiveInk(forDifference: -1)
        case 0:    return .secondary
        default:   return BookletStyle.adaptiveInk(forDifference: 2)
        }
    }
}

#Preview {
    HomeView(onOpenRound: { _ in }, onNewRound: {})
        .environmentObject(RoundStore())
        .environmentObject(TournamentStore())
        .environmentObject(SocialStore())
        .environmentObject(CardAppearance())
}
