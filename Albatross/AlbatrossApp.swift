import SwiftUI

enum AppState {
    case loading      // LandingView splash playing
    case signedOut    // No session — show SignInView
    case signedIn     // Active session — show ContentView
}

@main
struct AlbatrossApp: App {
    @StateObject private var authStore        = AuthStore()
    @StateObject private var roundStore       = RoundStore()
    @StateObject private var courseStore      = CourseStore()
    @StateObject private var socialStore      = SocialStore()
    @StateObject private var tournamentStore  = TournamentStore()

    @State private var appState: AppState = .loading
    @State private var selectedTab: Int = 1
    @State private var pendingRoundID: UUID? = nil
    @State private var pendingNewRound: Bool = false
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"

    /// Debug builds skip the sign-in screen so UI can be tested without credentials.
    /// Cloud sync and social features stay inactive because no session exists.
    /// Release builds always require sign-in.
    private static let skipsSignIn: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private func appStateAfterLanding() -> AppState {
        (Self.skipsSignIn || authStore.isSignedIn) ? .signedIn : .signedOut
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch appState {
                case .loading:
                    // LandingView drives the transition itself
                    LandingView(isShowing: Binding(
                        get: { appState == .loading },
                        set: { stillShowing in
                            if !stillShowing {
                                appState = appStateAfterLanding()
                            }
                        }
                    ))
                    .transition(.opacity)

                case .signedOut:
                    SignInView()
                        .transition(.opacity)

                case .signedIn:
                    ContentView(
                        selectedTab: $selectedTab,
                        pendingRoundID: $pendingRoundID,
                        pendingNewRound: $pendingNewRound
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.35), value: appState)
            .preferredColorScheme(preferredColorScheme)
            .environmentObject(authStore)
            .environmentObject(roundStore)
            .environmentObject(courseStore)
            .environmentObject(socialStore)
            .environmentObject(tournamentStore)
            .onAppear {
                // Wire stores together so RoundStore can check auth state
                roundStore.authStore = authStore
                authStore.roundStore = roundStore
                socialStore.authStore = authStore
                tournamentStore.authStore = authStore
                #if DEBUG
                // UI tests launch with this argument to start from one empty in-progress round.
                if CommandLine.arguments.contains("-uitest-seed-round"),
                   !roundStore.rounds.contains(where: { $0.courseName == "UI Test Course" }) {
                    roundStore.add(Round(courseName: "UI Test Course"))
                }
                #endif
            }
            // React to auth state changes that happen after initial load
            // (e.g. sign-in completes, session restored asynchronously)
            .onChange(of: authStore.isSignedIn) { _, signedIn in
                if appState != .loading {
                    withAnimation(.easeIn(duration: 0.35)) {
                        appState = appStateAfterLanding()
                    }
                }
                // Load social data when user signs in
                if signedIn {
                    Task { await socialStore.loadAll() }
                } else {
                    // Clear on sign-out
                    socialStore.following = []
                    socialStore.followers = []
                    socialStore.friendsFeed = []
                }
            }
            .onOpenURL { url in
                guard url.scheme == "albatross" else { return }

                // Widget / Control Center: start new round
                if url.host == "newround" {
                    selectedTab = 1
                    pendingNewRound = true
                    return
                }

                // Live Activity deep link: open existing round
                guard url.host == "round",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                      let roundID = UUID(uuidString: idString)
                else { return }
                selectedTab = 1
                pendingRoundID = roundID
            }
            // Control Center toggle writes a UserDefaults flag before opening the app;
            // pick it up when the app enters the foreground.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                let defaults = UserDefaults(suiteName: "group.TrujSoft.Albatross")
                guard defaults?.bool(forKey: "pendingNewRound") == true else { return }
                defaults?.removeObject(forKey: "pendingNewRound")
                selectedTab = 1
                pendingNewRound = true
            }
        }
    }
}
