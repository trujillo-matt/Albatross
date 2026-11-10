import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @State private var showUserSearch = false
    @State private var selectedProfile: UserProfile? = nil
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if socialStore.isLoadingFeed && socialStore.friendsFeed.isEmpty {
                    ProgressView()
                } else if socialStore.following.isEmpty {
                    emptyFollowingState
                } else if socialStore.friendsFeed.isEmpty {
                    emptyFeedState
                } else {
                    feedList
                }
            }
            .navigationTitle("Clubhouse")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showUserSearch = true }) {
                        Label("Find Friends", systemImage: "person.badge.plus")
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

    // MARK: - Empty states

    private var emptyFollowingState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .scaledFont(size: 56)
                .foregroundStyle(Color.accentColor.opacity(0.4))
            Text("Follow friends to see their rounds here")
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Find golfers you know and follow them to see their scores in your feed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { showUserSearch = true }) {
                Text("Find Friends")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressFeedback)
        }
        .padding(40)
    }

    private var emptyFeedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.slash")
                .scaledFont(size: 48)
                .foregroundStyle(.tertiary)
            Text("No rounds yet")
                .font(.body.weight(.semibold))
            Text("Your friends haven't posted any completed rounds yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(40)
    }

    // MARK: - Feed list

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(socialStore.friendsFeed) { item in
                    FeedItemCard(item: item) {
                        selectedProfile = item.profile
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .readableContentWidth()
        }
        .refreshable {
            await socialStore.loadFeed()
        }
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
    HomeView()
        .environmentObject(SocialStore())
}
