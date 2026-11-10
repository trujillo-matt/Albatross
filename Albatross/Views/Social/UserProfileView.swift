import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile

    @State private var theirRounds: [Round] = []
    @State private var isLoading = true
    @State private var showHeadToHead = false

    // MARK: - Computed

    private var completedRounds: [Round] { theirRounds.filter { $0.status == .completed } }

    private var bestScore: Int? { completedRounds.map { $0.totalScore }.min() }

    private var averageScore: Double? {
        guard !completedRounds.isEmpty else { return nil }
        let total = completedRounds.map { $0.totalScore }.reduce(0, +)
        return Double(total) / Double(completedRounds.count)
    }

    private var handicapIndex: Double? { Albatross.handicapIndex(for: completedRounds) }

    private var initials: String {
        let parts = profile.displayName.split(separator: " ")
        return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Profile card
                        profileCard
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 20)

                        // Stats strip
                        statsStrip
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        // Head to Head button (only show if user has rounds and so do we)
                        if !completedRounds.isEmpty,
                           let myProfile = authStore.currentProfile {
                            headToHeadButton(myProfile: myProfile)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }

                        // Their rounds list
                        if isLoading {
                            ProgressView()
                                .padding(.top, 20)
                        } else if completedRounds.isEmpty {
                            Text("No completed rounds yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        } else {
                            roundsList
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(profile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "xmark")
                    }
                }
            }
            .navigationDestination(isPresented: $showHeadToHead) {
                if let myProfile = authStore.currentProfile {
                    HeadToHeadView(
                        myProfile: myProfile,
                        theirProfile: profile,
                        theirRounds: completedRounds
                    )
                }
            }
            .task {
                theirRounds = await socialStore.loadRounds(for: profile.id)
                isLoading = false
            }
        }
    }

    // MARK: - Sub-views

    private var profileCard: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 16) {
                // Avatar initials
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 90, height: 110)
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 4) {
                    let parts = profile.displayName.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(parts[0]))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(String(parts[1]))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    } else {
                        Text(profile.displayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    if let username = profile.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let location = profile.location, !location.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .scaledFont(size: 11)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding(18)

            // Follow button (top right)
            FollowButton(userID: profile.id)
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.18, green: 0.22, blue: 0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statItem(label: "Rounds", value: "\(completedRounds.count)")
            Divider().frame(height: 32)
            statItem(label: "Best", value: bestScore.map { "\($0)" } ?? "—")
            Divider().frame(height: 32)
            statItem(label: "Average", value: averageScore.map { String(format: "%.1f", $0) } ?? "—")
            Divider().frame(height: 32)
            statItem(label: "HCP", value: handicapIndex.map { String(format: "%.1f", $0) } ?? "—")
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func headToHeadButton(myProfile: UserProfile) -> some View {
        Button(action: { showHeadToHead = true }) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .scaledFont(size: 14, weight: .semibold)
                Text("Head to Head")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.pressFeedback)
    }

    private var roundsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Rounds")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(completedRounds.prefix(20)) { round in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(round.courseName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let pars = round.effectivePars
                        let par = pars.reduce(0, +)
                        let diff = round.totalScore - par
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(round.totalScore)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.caption2)
                                .foregroundStyle(scoreColor(diff))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if round.id != completedRounds.prefix(20).last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        }
    }

    private func scoreColor(_ diff: Int) -> Color {
        switch diff {
        case ..<0: return .green
        case 0: return .secondary
        default: return .red
        }
    }
}
