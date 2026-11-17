import SwiftUI

struct UserSearchView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedProfile: UserProfile? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search by name or @username", text: $query)
                            .font(.callout)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: query) { _, newValue in
                                scheduleSearch(newValue)
                            }
                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Clear Search")
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if socialStore.isSearching {
                        ProgressView()
                            .padding(.top, 40)
                        Spacer()
                    } else if query.isEmpty {
                        emptyPrompt
                    } else if socialStore.searchResults.isEmpty {
                        noResults
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "xmark")
                    }
                }
            }
            .sheet(item: $selectedProfile) { profile in
                UserProfileView(profile: profile)
            }
        }
    }

    // MARK: - Sub-views

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            IconView("crossed-clubs", size: 48)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Search for golfers")
                .font(.body.weight(.semibold))
            Text("Find friends by their name or @username")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .scaledFont(size: 40)
                .foregroundStyle(.tertiary)
            Text("No golfers found")
                .font(.body.weight(.semibold))
            Text("Try a different name or username")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(40)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(socialStore.searchResults) { profile in
                    SearchResultRow(profile: profile) {
                        selectedProfile = profile
                    }
                    Divider().padding(.leading, 68)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Debounced search

    private func scheduleSearch(_ newQuery: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await socialStore.searchUsers(query: newQuery)
        }
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    @EnvironmentObject private var socialStore: SocialStore
    let profile: UserProfile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar initials circle
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let username = profile.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Follow / Following button
                FollowButton(userID: profile.id)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressFeedback)
    }

    private var initials: String {
        let parts = profile.displayName.split(separator: " ")
        return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
    }
}

// MARK: - Reusable Follow button

struct FollowButton: View {
    @EnvironmentObject private var socialStore: SocialStore
    let userID: UUID
    @State private var isLoading = false

    private var isFollowing: Bool { socialStore.isFollowing(userID) }

    var body: some View {
        Button(action: toggle) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.footnote)
                .foregroundStyle(isFollowing ? .secondary : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isFollowing
                        ? Color(.tertiarySystemGroupedBackground)
                        : Color.accentColor.opacity(0.12)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.pressFeedback)
        .disabled(isLoading)
    }

    private func toggle() {
        isLoading = true
        Task {
            defer { isLoading = false }
            if isFollowing {
                await socialStore.unfollow(userID: userID)
            } else {
                await socialStore.follow(userID: userID)
            }
        }
    }
}
