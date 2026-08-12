import Combine
import Foundation
import Supabase
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var currentProfile: UserProfile? = nil
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Set by AlbatrossApp after both stores are initialised
    weak var roundStore: RoundStore?

    // MARK: - Init

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Session restore

    private func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            isSignedIn = true
            await fetchOrCreateProfile(userID: session.user.id, fallbackName: session.user.email ?? "")
            await roundStore?.syncFromCloud()
        } catch {
            isSignedIn = false
        }
    }

    // MARK: - Sign in

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            await fetchOrCreateProfile(userID: session.user.id, fallbackName: email)
            isSignedIn = true
            await migrateLocalRoundsIfNeeded()
            await roundStore?.syncFromCloud()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Sign up

    func signUp(email: String, password: String, firstName: String, username: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            // Pass firstName and username as metadata so the DB trigger can
            // create the profile row using security definer (bypasses RLS).
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: [
                    "full_name": .string(firstName),
                    "username":  .string(username)
                ]
            )
            let user = response.user

            // Give the trigger a moment to create the profile row, then fetch/create it
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await fetchOrCreateProfile(userID: user.id, fallbackName: firstName, fallbackUsername: username)
            isSignedIn = true
            await migrateLocalRoundsIfNeeded()
            await roundStore?.syncFromCloud()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Sign out

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
            isSignedIn = false
            currentProfile = nil
        }
    }

    // MARK: - Profile fetch (with auto-create fallback)

    /// Fetches the profile row. If none exists (trigger may have failed), creates one.
    func fetchOrCreateProfile(userID: UUID, fallbackName: String, fallbackUsername: String? = nil) async {
        // First try to fetch existing row
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            currentProfile = profile
            print("AuthStore: fetchProfile success — '\(profile.displayName)', @\(profile.username ?? "nil")")
            return
        } catch {
            print("AuthStore: fetchProfile failed, will upsert — \(error)")
        }

        // Row doesn't exist (or fetch failed) — upsert a new one
        struct ProfileUpsert: Encodable {
            let id: UUID
            let display_name: String
            let username: String?
        }

        let upsertPayload = ProfileUpsert(
            id: userID,
            display_name: fallbackName,
            username: fallbackUsername
        )

        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .upsert(upsertPayload, onConflict: "id")
                .select()
                .single()
                .execute()
                .value
            currentProfile = profile
            print("AuthStore: profile upserted — '\(profile.displayName)'")
        } catch {
            print("AuthStore: profile upsert also failed — \(error)")
        }
    }

    // MARK: - Profile update

    func updateProfile(
        displayName: String,
        username: String,
        homeCourse: String? = nil,
        location: String? = nil
    ) async {
        // Get the userID from current profile or from the active session
        let userID: UUID
        if let id = currentProfile?.id {
            userID = id
        } else if let session = try? await supabase.auth.session {
            userID = session.user.id
        } else {
            print("AuthStore: updateProfile — no user ID available")
            return
        }

        struct ProfileUpdate: Encodable {
            let display_name: String
            let username: String
            let home_course: String?
            let location: String?
            let updated_at: String
        }

        let payload = ProfileUpdate(
            display_name: displayName,
            username: username,
            home_course: homeCourse.flatMap { $0.isEmpty ? nil : $0 },
            location: location.flatMap { $0.isEmpty ? nil : $0 },
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        do {
            let updated: UserProfile = try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: userID)
                .select()
                .single()
                .execute()
                .value
            currentProfile = updated
            print("AuthStore: updateProfile success — '\(updated.displayName)'")
        } catch {
            print("AuthStore: updateProfile error — \(error)")
            errorMessage = "Failed to save profile. Please try again."
        }
    }

    // MARK: - Local round migration

    private func migrateLocalRoundsIfNeeded() async {
        let didMigrate = UserDefaults.standard.bool(forKey: "didMigrateRounds")
        guard !didMigrate, let store = roundStore else { return }
        for round in store.rounds {
            await store.syncToCloud(round)
        }
        UserDefaults.standard.set(true, forKey: "didMigrateRounds")
    }

    // MARK: - Error formatting

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("invalid login") || msg.contains("credentials") {
            return "Incorrect email or password."
        } else if msg.contains("already registered") || msg.contains("already exists") {
            return "An account with that email already exists."
        } else if msg.contains("network") || msg.contains("connection") {
            return "No internet connection. Please try again."
        }
        return error.localizedDescription
    }
}
