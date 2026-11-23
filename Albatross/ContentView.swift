import SwiftUI

struct ContentView: View {
    // All stores flow down from AlbatrossApp via environment
    @Environment(RoundStore.self) private var roundStore
    @Environment(CourseStore.self) private var courseStore
    @Environment(AuthStore.self) private var authStore
    @Environment(SocialStore.self) private var socialStore

    @Binding var selectedTab: Int
    @Binding var pendingRoundID: UUID?
    @Binding var pendingNewRound: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Clubhouse", image: "icon-clubhouse", value: 0) {
                HomeView(
                    onOpenRound: { roundID in
                        selectedTab = 1
                        pendingRoundID = roundID
                    },
                    onNewRound: {
                        selectedTab = 1
                        pendingNewRound = true
                    }
                )
            }

            Tab("Scorecards", image: "icon-scorecard", value: 1) {
                ScorecardsView(pendingRoundID: $pendingRoundID, pendingNewRound: $pendingNewRound)
            }

            Tab("Tournaments", image: "icon-trophy", value: 4) {
                TournamentListView()
            }

            Tab("Stats", image: "icon-stats", value: 2) {
                StatsView()
            }

            Tab("Profile", image: "icon-member", value: 3) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sidebarByDefaultWhereAvailable()
    }
}

private extension View {
    /// On iOS 27 the tabs start in the sidebar, which suits the wide inner display.
    /// The user can still switch to the tab bar; earlier systems keep the automatic choice.
    @ViewBuilder
    func sidebarByDefaultWhereAvailable() -> some View {
        if #available(iOS 27.0, *) {
            self.defaultTabBarPlacement(.sidebar)
        } else {
            self
        }
    }
}

#Preview {
    ContentView(selectedTab: .constant(1), pendingRoundID: .constant(nil), pendingNewRound: .constant(false))
        .environment(RoundStore())
        .environment(CourseStore())
        .environment(AuthStore())
        .environment(SocialStore())
}
