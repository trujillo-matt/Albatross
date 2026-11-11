import SwiftUI

/// Who you are as a golfer: a membership card in your paper and ink, then friends, tournaments and settings.
struct ProfileView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var appearance: CardAppearance

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showSignOutConfirm = false
    @State private var showUserSearch = false
    @State private var selectedProfile: UserProfile? = nil
    @State private var avatarImage: UIImage? = nil

    private var completedRounds: [Round] {
        roundStore.rounds.filter { $0.status == .completed }
    }

    private var handicapIndex: Double? { Albatross.handicapIndex(for: completedRounds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    membershipCard

                    friendsSection

                    shortcutsSection

                    Button(role: .destructive) { showSignOutConfirm = true } label: {
                        Text("Sign out")
                            .font(.body)
                            .foregroundStyle(Color(.systemRed))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.pressFeedback)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .readableContentWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEditProfile = true }
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
            .confirmationDialog("Sign out", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { authStore.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to reach your rounds.")
            }
            .onAppear { loadAvatar() }
        }
    }

    // MARK: - Membership card

    /// The moment on this screen: a card printed on the player's paper in their ink,
    /// with the handicap written in pencil, as on a scorecard.
    private var membershipCard: some View {
        let profile = authStore.currentProfile
        let name = profile?.displayName ?? ""
        let username = profile?.username ?? ""
        let location = profile?.location ?? ""
        let homeCourse = profile?.homeCourse ?? ""
        let paper = appearance.paper.color ?? CardAppearance.cream
        let ink = appearance.accent.color ?? CardAppearance.fairway

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? "Your name" : name)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    if !location.isEmpty {
                        Text(location)
                            .font(.footnote)
                            .foregroundStyle(ink.opacity(0.65))
                    }
                }
                Spacer(minLength: 8)
                avatar(ink: ink)
            }

            Rectangle()
                .fill(ink.opacity(0.3))
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Home course")
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.65))
                    Text(homeCourse.isEmpty ? "Not set" : homeCourse)
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(handicapIndex.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.custom(BookletStyle.pencilFontName, size: 44))
                        .foregroundStyle(BookletStyle.pencilGraphite)
                    Text(handicapIndex == nil ? "Needs 3 rounds" : "Handicap index")
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.65))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ink.opacity(0.45), lineWidth: 1)
                .padding(4)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func avatar(ink: Color) -> some View {
        let name = authStore.currentProfile?.displayName ?? ""
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    ink.opacity(0.12)
                    Text(initialsFromName(name))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ink.opacity(0.35), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                Text("Friends")
                    .font(.title3.weight(.medium))
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("\(socialStore.following.count) following · \(socialStore.followers.count) followers")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(socialStore.following) { profile in
                    Button { selectedProfile = profile } label: {
                        friendRow(profile: profile)
                    }
                    .buttonStyle(.pressFeedback)
                    Divider().padding(.leading, 64)
                }
                Button { showUserSearch = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .frame(width: 40)
                            .foregroundStyle(Color.accentColor)
                        Text("Find friends")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressFeedback)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func friendRow(profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            Text(initialsFromName(profile.displayName))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let latest = socialStore.friendsFeed.first(where: { $0.profile.id == profile.id }) {
                let difference = latest.round.totalScore - latest.round.effectivePars.reduce(0, +)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(latest.round.totalScore)")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(difference == 0 ? "E" : difference > 0 ? "+\(difference)" : "\(difference)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BookletStyle.adaptiveInk(forDifference: difference == 0 ? 0 : (difference < 0 ? -1 : 2)))
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    // MARK: - Tournaments and settings

    private var shortcutsSection: some View {
        VStack(spacing: 0) {
            Button { showSettings = true } label: {
                shortcutRow(title: "Settings", detail: nil, systemImage: "gearshape")
            }
            .buttonStyle(.pressFeedback)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortcutRow(title: String, detail: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 40)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func loadAvatar() {
        if let data = try? Data(contentsOf: UserProfile.localAvatarURL),
           let image = UIImage(data: data) {
            avatarImage = image
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
                            .font(.callout)
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
                        .font(.caption)
                }

                Section {
                    NavigationLink {
                        ScrollView { CardStyleForm().padding(20) }
                            .navigationTitle("Scorecard")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Paper, ink and putts", systemImage: "paintpalette")
                            .font(.callout)
                    }
                } header: {
                    Text("Scorecard")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .albatrossConfirm) {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
