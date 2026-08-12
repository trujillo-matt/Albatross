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
            HomeView()
                .tabItem {
                    Label("Clubhouse", systemImage: "house.fill")
                }
                .tag(0)

            ScorecardsView(pendingRoundID: $pendingRoundID, pendingNewRound: $pendingNewRound)
                .tabItem {
                    Label("Scorecards", systemImage: "list.clipboard.fill")
                }
                .tag(1)

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
                .tag(3)
        }
        .tint(.accentColor)
    }
}

#Preview {
    ContentView(selectedTab: .constant(1), pendingRoundID: .constant(nil), pendingNewRound: .constant(false))
        .environmentObject(RoundStore())
        .environmentObject(CourseStore())
        .environmentObject(AuthStore())
        .environmentObject(SocialStore())
}
