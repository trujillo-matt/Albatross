import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var socialStore: SocialStore

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showSignOutConfirm = false
    @State private var showUserSearch = false
    @State private var selectedProfile: UserProfile? = nil
    @State private var avatarImage: UIImage? = nil

    // MARK: - Computed stats

    private var completedRounds: [Round] {
        roundStore.rounds.filter { $0.status == .completed }
    }

    private var bestScore: Int? {
        completedRounds.map { $0.totalScore }.min()
    }

    private var averageScore: Double? {
        guard !completedRounds.isEmpty else { return nil }
        let total = completedRounds.map { $0.totalScore }.reduce(0, +)
        return Double(total) / Double(completedRounds.count)
    }

    private var handicapIndex: Double? { Albatross.handicapIndex(for: completedRounds) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // ── Avatar + name ────────────────────────────────
                        profileHeader
                            .padding(.top, 24)
                            .padding(.bottom, 24)

                        // ── Stats strip ──────────────────────────────────
                        statsStrip
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        // ── Handicap card ────────────────────────────────
                        handicapCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        // ── Friends ──────────────────────────────────────
                        friendsSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        // ── Actions ──────────────────────────────────────
                        actionsSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    initialDisplayName: authStore.currentProfile?.displayName ?? "",
                    initialUsername: authStore.currentProfile?.username ?? "",
                    initialHomeCourse: authStore.currentProfile?.homeCourse ?? "",
                    initialLocation: authStore.currentProfile?.location ?? ""
                )
                .onDisappear { loadAvatar() }
            }
            .sheet(isPresented: $showUserSearch) {
                UserSearchView()
            }
            .sheet(item: $selectedProfile) { profile in
                UserProfileView(profile: profile)
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { authStore.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to access your rounds.")
            }
            .onAppear { loadAvatar() }
        }
    }

    // MARK: - Profile header card

    private var profileHeader: some View {
        let profile = authStore.currentProfile
        let name = profile?.displayName ?? ""
        let username = profile?.username ?? ""
        let homeCourse = profile?.homeCourse ?? ""
        let location = profile?.location ?? ""

        return VStack(spacing: 12) {
            // ── Dark green card ──────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 16) {
                    // Avatar — tall rounded rectangle
                    ZStack {
                        if let img = avatarImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 110, height: 130)
                                .overlay(
                                    Text(initialsFromName(name))
                                        .font(.custom("Baskerville-Bold", size: 38))
                                        .foregroundStyle(.white.opacity(0.85))
                                )
                        }
                    }

                    // Name, username, location
                    VStack(alignment: .leading, spacing: 4) {
                        // Split name across two lines if it contains a space
                        let parts = name.split(separator: " ", maxSplits: 1)
                        if parts.count == 2 {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(parts[0]))
                                    .font(.custom("Baskerville-Bold", size: 26))
                                    .foregroundStyle(.white)
                                Text(String(parts[1]))
                                    .font(.custom("Baskerville-Bold", size: 26))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Text(name.isEmpty ? "—" : name)
                                .font(.custom("Baskerville-Bold", size: 26))
                                .foregroundStyle(.white)
                        }

                        if !username.isEmpty {
                            Text("@\(username)")
                                .font(.custom("Baskerville", size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if !location.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(location)
                                    .font(.custom("Baskerville", size: 12))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.top, 6)

                    Spacer()
                }
                .padding(18)

                // Home course badge (top right corner)
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(homeCourse.isEmpty ? "Home Course" : homeCourse)
                        .font(.custom("Baskerville", size: 9))
                        .foregroundStyle(.white.opacity(homeCourse.isEmpty ? 0.35 : 0.65))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 64)
                }
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.accentColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // ── Edit Profile pill (below card) ───────────────────────────
            Button(action: { showEditProfile = true }) {
                Text("Edit Profile")
                    .font(.custom("Baskerville", size: 14))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statItem(label: "Rounds", value: "\(completedRounds.count)")
            Divider().frame(height: 32)
            statItem(label: "Best", value: bestScore.map { "\($0)" } ?? "—")
            Divider().frame(height: 32)
            statItem(label: "Average", value: averageScore.map { String(format: "%.1f", $0) } ?? "—")
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.custom("Baskerville-Bold", size: 20))
                .foregroundStyle(.primary)
            Text(label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Handicap card

    private var handicapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handicap Index")
                .font(.custom("Baskerville", size: 13))
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                if let hcp = handicapIndex {
                    Text(String(format: "%.1f", hcp))
                        .font(.custom("Baskerville-Bold", size: 40))
                        .foregroundStyle(.primary)
                    Text("HCP")
                        .font(.custom("Baskerville", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                } else {
                    Text("—")
                        .font(.custom("Baskerville-Bold", size: 40))
                        .foregroundStyle(.secondary)
                    Text(completedRounds.count < 3 ? "Need \(3 - completedRounds.count) more rounds" : "HCP")
                        .font(.custom("Baskerville", size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Friends section

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Friends")
                    .font(.custom("Baskerville-Bold", size: 18))

                Spacer()

                // Follower / Following counts
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text("\(socialStore.followers.count)")
                            .font(.custom("Baskerville-Bold", size: 14))
                            .foregroundStyle(.primary)
                        Text("Followers")
                            .font(.custom("Baskerville", size: 10))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        Text("\(socialStore.following.count)")
                            .font(.custom("Baskerville-Bold", size: 14))
                            .foregroundStyle(.primary)
                        Text("Following")
                            .font(.custom("Baskerville", size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                // Find Friends button
                Button(action: { showUserSearch = true }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            if socialStore.following.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor.opacity(0.35))
                    Text("Follow friends to see them here")
                        .font(.custom("Baskerville", size: 13))
                        .foregroundStyle(.secondary)
                    Button(action: { showUserSearch = true }) {
                        Text("Find Friends")
                            .font(.custom("Baskerville-Bold", size: 13))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.bottom, 4)
            } else {
                // Following list
                VStack(spacing: 0) {
                    ForEach(socialStore.following) { profile in
                        Button(action: { selectedProfile = profile }) {
                            friendRow(profile: profile)
                        }
                        .buttonStyle(.plain)

                        if profile.id != socialStore.following.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    private func friendRow(profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(initials(for: profile.displayName))
                    .font(.custom("Baskerville-Bold", size: 14))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.custom("Baskerville-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.custom("Baskerville", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Latest round score from feed
            if let latest = socialStore.friendsFeed.first(where: { $0.profile.id == profile.id }) {
                let diff = latest.round.totalScore - latest.round.effectivePars.reduce(0, +)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(latest.round.totalScore)")
                        .font(.custom("Baskerville-Bold", size: 16))
                        .foregroundStyle(.primary)
                    Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                        .font(.custom("Baskerville", size: 10))
                        .foregroundStyle(diff < 0 ? .green : diff == 0 ? .secondary : .red)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button(role: .destructive, action: { showSignOutConfirm = true }) {
                HStack {
                    Spacer()
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.custom("Baskerville", size: 16))
                    Spacer()
                }
                .padding(.vertical, 15)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Helpers

    private func loadAvatar() {
        if let data = try? Data(contentsOf: UserProfile.localAvatarURL),
           let img = UIImage(data: data) {
            avatarImage = img
        } else {
            avatarImage = nil
        }
    }

    private func initialsFromName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
        return initials.isEmpty ? "?" : initials
    }
}

// MARK: - Settings sheet (unchanged)

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Dark Mode", systemImage: "moon.fill")
                            .font(.custom("Baskerville", size: 16))
                        Spacer()
                        Picker("", selection: $colorSchemePreference) {
                            Text("Off").tag("light")
                            Text("On").tag("dark")
                            Text("Auto").tag("system")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                } header: {
                    Text("Appearance")
                        .font(.custom("Baskerville", size: 12))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("Baskerville", size: 16))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthStore())
        .environmentObject({
            let s = RoundStore()
            var r1 = Round(courseName: "Augusta National")
            r1.scores = Array(repeating: 4, count: 18)
            r1.status = .completed
            s.add(r1)
            return s
        }())
}
