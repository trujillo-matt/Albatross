import SwiftUI

struct ContentView: View {
    // All stores flow down from AlbatrossApp via environment
    @EnvironmentObject private var roundStore:  RoundStore
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var authStore:   AuthStore
    @EnvironmentObject private var socialStore: SocialStore

    @Binding var selectedTab: Int
    @Binding var pendingRoundID: UUID?
    @Binding var pendingNewRound: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Clubhouse", systemImage: "house.fill", value: 0) {
                HomeView()
            }

            Tab("Scorecards", systemImage: "list.clipboard.fill", value: 1) {
                ScorecardsView(pendingRoundID: $pendingRoundID, pendingNewRound: $pendingNewRound)
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: 2) {
                StatsView()
            }

            Tab("Profile", systemImage: "person.crop.circle.fill", value: 3) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sidebarByDefaultWhereAvailable()
        .tint(.accentColor)
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
        .environmentObject(RoundStore())
        .environmentObject(CourseStore())
        .environmentObject(AuthStore())
        .environmentObject(SocialStore())
}
