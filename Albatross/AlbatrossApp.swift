import SwiftUI

enum AppState {
    case loading      // LandingView splash playing
    case signedOut    // No session — show SignInView
    case signedIn     // Active session — show ContentView
}

@main
struct AlbatrossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authStore        = AuthStore()
    @State private var roundStore       = RoundStore()
    @State private var courseStore      = CourseStore()
    @State private var socialStore      = SocialStore()
    @State private var tournamentStore  = TournamentStore()
    @State private var appearance       = CardAppearance()
    @State private var weatherStore     = WeatherForecastStore()

    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState = .loading
    #if DEBUG
    @State private var hasAppliedDebugArguments = false
    #endif
    @State private var selectedTab: Int = 1
    @State private var pendingRoundID: UUID? = nil
    @State private var pendingNewRound: Bool = false
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"
    /// True once someone chose to use the app without signing in. Cleared from Profile to sign in later.
    @AppStorage("continuesWithoutAccount") private var continuesWithoutAccount = false

    /// Debug builds skip the sign-in screen so UI can be tested without credentials.
    /// Cloud sync and social features stay inactive because no session exists.
    /// Release builds always require sign-in.
    private static let skipsSignIn: Bool = {
        #if DEBUG
        // -show-sign-in brings the sign-in screen back so it can be tested.
        return !CommandLine.arguments.contains("-show-sign-in")
        #else
        return false
        #endif
    }()

    private func appStateAfterLanding() -> AppState {
        (Self.skipsSignIn || authStore.isSignedIn || continuesWithoutAccount) ? .signedIn : .signedOut
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
                    SignInView(onContinueWithoutAccount: {
                        continuesWithoutAccount = true
                        appState = .signedIn
                    })
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
            .environment(authStore)
            .environment(roundStore)
            .environment(courseStore)
            .environment(socialStore)
            .environment(tournamentStore)
            .environment(weatherStore)
            .environment(appearance)
            // The chosen ink tints controls and highlights across the app.
            .tint(appearance.tint)
            .onAppear {
                wireStores()
                NewsAlerts.shared.install()
                tournamentStore.startWatchingNews()
                #if DEBUG
                // The screen can appear more than once; the launch arguments are applied only the first time.
                if !hasAppliedDebugArguments {
                    hasAppliedDebugArguments = true
                    // Launching with -demo-tournament shows a made-up tournament without a cloud account.
                    let wantsLargeDemo = CommandLine.arguments.contains(TournamentDemo.largeLaunchArgument)
                    if wantsLargeDemo || CommandLine.arguments.contains(TournamentDemo.launchArgument) {
                        authStore.seedDemoProfile(TournamentDemo.me)
                        tournamentStore.installDemoTournament(large: wantsLargeDemo)
                        socialStore.installDemoFriends()
                    }
                    // -demo-news-alert sends one fresh birdie through the phone alert path a few seconds after launch.
                    if CommandLine.arguments.contains("-demo-news-alert") {
                        Task {
                            try? await Task.sleep(for: .seconds(8))
                            if let item = TournamentDemo.freshNewsItem(for: tournamentStore.myTournaments) {
                                await tournamentStore.postDemoNewsAlert(item)
                            }
                        }
                    }
                    // -demo-weather shows a sample forecast under the tournament info.
                    if CommandLine.arguments.contains("-demo-weather"), let tournament = tournamentStore.myTournaments.first {
                        weatherStore.seedDemo(for: tournament)
                    }
                    // -demo-rounds fills the library so stacked cards can be seen.
                    if CommandLine.arguments.contains("-demo-rounds") {
                        roundStore.installDemoRounds()
                    }
                    // -show-sign-in also forgets an earlier "continue without an account", so the screen can be tested.
                    if CommandLine.arguments.contains("-show-sign-in") {
                        continuesWithoutAccount = false
                    }
                    // -demo-tab N opens that tab first (0 Clubhouse, 1 Scorecards, 4 Tournaments, 2 Stats, 3 Profile).
                    let arguments = CommandLine.arguments
                    if let flag = arguments.firstIndex(of: "-demo-tab"), arguments.indices.contains(flag + 1),
                       let tab = Int(arguments[flag + 1]) {
                        selectedTab = tab
                    }
                    // UI tests launch with this argument to start from one empty in-progress round.
                    if CommandLine.arguments.contains("-uitest-seed-round"),
                       !roundStore.rounds.contains(where: { $0.courseName == "UI Test Course" }) {
                        roundStore.add(Round(courseName: "UI Test Course"))
                    }
                }
                #endif
            }
            // React to auth state changes that happen after initial load
            // (e.g. sign-in completes, session restored asynchronously)
            .onChange(of: continuesWithoutAccount) { _, usesNoAccount in
                // Choosing "Sign in" from Profile puts the sign-in screen back.
                if !usesNoAccount, !authStore.isSignedIn, !Self.skipsSignIn, appState == .signedIn {
                    appState = .signedOut
                }
            }
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
            // Leaving the app asks iOS for a news check later, so alerts can arrive while it is closed.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { NewsAlerts.shared.scheduleBackgroundRefresh() }
            }
        }
        .backgroundTask(.appRefresh(NewsAlerts.refreshIdentifier)) {
            await MainActor.run {
                wireStores()
                NewsAlerts.shared.install()
                NewsAlerts.shared.scheduleBackgroundRefresh()
            }
            await tournamentStore.refreshNewsInBackground()
            await weatherStore.alertAboutRain(tournaments: tournamentStore.myTournaments, courses: courseStore.allCourses)
        }
    }

    /// Stores that need each other, joined. Also done when iOS wakes the app in the background, before any screen exists.
    private func wireStores() {
        roundStore.authStore = authStore
        authStore.roundStore = roundStore
        socialStore.authStore = authStore
        tournamentStore.authStore = authStore
    }
}
