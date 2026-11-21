import SwiftUI

struct NewTournamentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var socialStore: SocialStore

    // ── Step tracking ────────────────────────────────────────────────────
    @State private var step = 1

    // ── Step 1 ───────────────────────────────────────────────────────────
    @State private var name: String = ""
    @State private var matchType: TournamentMatchType = .bestBall
    @State private var days: Int = 3

    // ── Step 2 ───────────────────────────────────────────────────────────
    @State private var courseNames: [String] = ["", "", ""]
    @State private var matchTypes: [TournamentMatchType] = [.bestBall, .bestBall, .bestBall]
    /// An optional second session per day (the afternoon), with its own format.
    @State private var secondSessions: [TournamentMatchType?] = [nil, nil, nil]

    // ── Step 3 ───────────────────────────────────────────────────────────
    @State private var searchQuery: String = ""
    @State private var invitedProfiles: [UserProfile] = []

    @State private var isCreating = false
    /// Set once the tournament exists but some invites failed, so a second tap closes instead of creating again.
    @State private var tournamentWasCreated = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1:  step1View
                case 2:  step2View
                default: step3View
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .albatrossConfirm) {
                    if step < 3 {
                        Button { advanceStep() } label: {
                            Label("Next", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(!canAdvance)
                    } else {
                        Button(action: createTournament) {
                            if isCreating {
                                ProgressView()
                            } else {
                                Label(tournamentWasCreated ? "Done" : "Create", systemImage: "checkmark")
                            }
                        }
                        .disabled(isCreating)
                    }
                }
            }
        }
        .onChange(of: days) { _, newValue in
            adjustCourseNames(to: newValue)
        }
    }

    // MARK: - Step 1: Name, type, matches

    private var step1View: some View {
        Form {
            Section("Tournament name") {
                TextField("e.g. Ryder Cup 2025", text: $name)
                    .font(.callout)
            }

            Section {
                Stepper(value: $days, in: 1...7) {
                    HStack {
                        Text("Days")
                            .font(.callout)
                        Spacer()
                        Text("\(days)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } header: {
                Text("Days of play")
            } footer: {
                Text("Each day has its own course and one or two sessions, each with a format. The matches in a session come from the players: every player plays once, so singles make one match per player and pairs make half as many. Extra players sit out, and captains call out who plays whom before each session. Points to win is set when the tournament starts.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Step 2: Courses + formats

    private var step2View: some View {
        Form {
            Section {
                ForEach(0..<days, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Day \(index + 1)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("Course name (optional)", text: courseNameBinding(for: index))
                            .font(.callout)

                        Picker("Format", selection: matchTypeBinding(for: index)) {
                            ForEach(TournamentMatchType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Add an afternoon session", isOn: hasSecondBinding(for: index))
                            .font(.callout)
                        if hasSecondBinding(for: index).wrappedValue {
                            Picker("Afternoon format", selection: secondTypeBinding(for: index)) {
                                ForEach(TournamentMatchType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Course and format for each day")
            } footer: {
                Text("Course names can be updated later from the tournament detail page.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Step 3: Invite players

    private var step3View: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name or username", text: $searchQuery)
                    .font(.subheadline)
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
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.pressFeedback)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Invited chips
            if !invitedProfiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(invitedProfiles) { profile in
                            inviteChip(profile)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .clippedToHorizontalSafeArea()
                .padding(.bottom, 12)
            }

            Divider()

            // Search results
            if socialStore.isSearching {
                ProgressView()
                    .padding(.top, 40)
                Spacer()
            } else if !socialStore.searchResults.isEmpty {
                List {
                    ForEach(socialStore.searchResults) { profile in
                        let alreadyInvited = invitedProfiles.contains(where: { $0.id == profile.id })
                        Button(action: {
                            if alreadyInvited {
                                invitedProfiles.removeAll { $0.id == profile.id }
                            } else {
                                invitedProfiles.append(profile)
                            }
                        }) {
                            HStack(spacing: 12) {
                                avatarView(profile, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let username = profile.username {
                                        Text("@\(username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if alreadyInvited {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.pressFeedback)
                    }
                }
                .listStyle(.plain)
            } else if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .scaledFont(size: 36)
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                    Text("Search for players to invite")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("You can also invite players after creating the tournament.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 40)
                Spacer()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .scaledFont(size: 28)
                        .foregroundStyle(.tertiary)
                    Text("No players found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                Spacer()
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Subviews

    private func inviteChip(_ profile: UserProfile) -> some View {
        HStack(spacing: 6) {
            Text(profile.displayName)
                .font(.footnote)
                .foregroundStyle(.primary)
            Button(action: { invitedProfiles.removeAll { $0.id == profile.id } }) {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityLabel("Remove \(profile.displayName)")
            }
            .buttonStyle(.pressFeedback)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func avatarView(_ profile: UserProfile, size: CGFloat) -> some View {
        if let urlString = profile.avatarURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.accentColor.opacity(0.2)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    // MARK: - Helpers

    private var stepTitle: String {
        switch step {
        case 1: return "New Tournament"
        case 2: return "Courses"
        default: return "Invite players"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return true // course names are optional
        default: return true
        }
    }

    private func advanceStep() {
        withAnimation { step += 1 }
    }

    private func adjustCourseNames(to count: Int) {
        if courseNames.count < count {
            courseNames.append(contentsOf: Array(repeating: "", count: count - courseNames.count))
            matchTypes.append(contentsOf: Array(repeating: .bestBall, count: count - matchTypes.count))
            secondSessions.append(contentsOf: Array(repeating: nil, count: max(0, count - secondSessions.count)))
        } else if courseNames.count > count {
            courseNames = Array(courseNames.prefix(count))
            matchTypes = Array(matchTypes.prefix(count))
            secondSessions = Array(secondSessions.prefix(count))
        }
    }

    private func hasSecondBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { index < secondSessions.count && secondSessions[index] != nil },
            set: { on in
                if index < secondSessions.count { secondSessions[index] = on ? .alternateShot : nil }
            }
        )
    }

    private func secondTypeBinding(for index: Int) -> Binding<TournamentMatchType> {
        Binding(
            get: { (index < secondSessions.count ? secondSessions[index] : nil) ?? .alternateShot },
            set: { value in
                if index < secondSessions.count { secondSessions[index] = value }
            }
        )
    }

    private func courseNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < courseNames.count ? courseNames[index] : "" },
            set: { value in
                if index < courseNames.count { courseNames[index] = value }
            }
        )
    }

    private func matchTypeBinding(for index: Int) -> Binding<TournamentMatchType> {
        Binding(
            get: { index < matchTypes.count ? matchTypes[index] : .bestBall },
            set: { value in
                if index < matchTypes.count { matchTypes[index] = value }
            }
        )
    }

    private func createTournament() {
        if tournamentWasCreated { dismiss(); return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let names = courseNames.map { $0.trimmingCharacters(in: .whitespaces) }
                let tournament = try await tournamentStore.createTournament(
                    name: name.trimmingCharacters(in: .whitespaces),
                    matchType: matchTypes.first ?? .bestBall,
                    days: days,
                    courseNames: names,
                    matchTypes: matchTypes,
                    secondSessionTypes: secondSessions
                )
                // Send invites, remembering which ones fail so they are not lost silently
                var failedNames: [String] = []
                for profile in invitedProfiles {
                    do {
                        try await tournamentStore.invitePlayer(tournamentID: tournament.id, userID: profile.id)
                    } catch {
                        failedNames.append(profile.displayName)
                    }
                }
                await MainActor.run {
                    isCreating = false
                    if failedNames.isEmpty {
                        dismiss()
                    } else {
                        tournamentWasCreated = true
                        errorMessage = "The tournament was created, but these invites did not go through: \(failedNames.joined(separator: ", ")). Invite them again from the tournament's player list."
                    }
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
