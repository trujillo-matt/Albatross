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
            Tab(AppTab.clubhouse.title, image: AppTab.clubhouse.icon, value: AppTab.clubhouse.rawValue) {
                HomeView(
                    onOpenRound: { roundID in
                        selectedTab = AppTab.scorecards.rawValue
                        pendingRoundID = roundID
                    },
                    onNewRound: {
                        selectedTab = AppTab.scorecards.rawValue
                        pendingNewRound = true
                    }
                )
            }

            Tab(AppTab.scorecards.title, image: AppTab.scorecards.icon, value: AppTab.scorecards.rawValue) {
                ScorecardsView(pendingRoundID: $pendingRoundID, pendingNewRound: $pendingNewRound)
            }

            Tab(AppTab.tournaments.title, image: AppTab.tournaments.icon, value: AppTab.tournaments.rawValue) {
                TournamentListView()
            }

            Tab(AppTab.stats.title, image: AppTab.stats.icon, value: AppTab.stats.rawValue) {
                StatsView()
            }

            Tab(AppTab.profile.title, image: AppTab.profile.icon, value: AppTab.profile.rawValue) {
                ProfileView()
            }
        }
        .environment(\.tabSelection, $selectedTab)
    }
}

/// The five sections of the app, in the order they are listed.
enum AppTab: Int, CaseIterable, Identifiable {
    case clubhouse = 0, scorecards = 1, tournaments = 4, stats = 2, profile = 3

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .clubhouse: "Clubhouse"
        case .scorecards: "Scorecards"
        case .tournaments: "Tournaments"
        case .stats: "Stats"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .clubhouse: "icon-clubhouse"
        case .scorecards: "icon-scorecard"
        case .tournaments: "icon-trophy"
        case .stats: "icon-stats"
        case .profile: "icon-member"
        }
    }

    /// Display order: the tournaments section sits after the scorecards.
    static let ordered: [AppTab] = [.clubhouse, .scorecards, .tournaments, .stats, .profile]
}

extension EnvironmentValues {
    /// The selected section, so a screen can offer the section menu without being handed the binding.
    @Entry var tabSelection: Binding<Int>?
}

/// The button in the corner that opens the sections as a bubble. The menu grows out of the button,
/// and the current section has a checkmark.
private struct TabMenuButton: View {
    @Binding var selection: Int

    var body: some View {
        Menu {
            Picker("Sections", selection: $selection) {
                ForEach(AppTab.ordered) { tab in
                    Label(tab.title, image: tab.icon).tag(tab.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sections", systemImage: "sidebar.left")
        }
    }
}

private struct TabMenuToolbar: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabSelection) private var selection

    func body(content: Content) -> some View {
        // A wide screen (an open iPhone Duo, an iPad) gives its whole width to the screen itself: the sections are one tap
        // away in a bubble from a toolbar button instead of a sidebar or tab bar. This sits inside the section's own
        // navigation stack so a screen pushed on top, like an open scorecard, can still hide the tab bar itself.
        content
            .toolbarVisibility(horizontalSizeClass == .regular ? .hidden : .automatic, for: .tabBar)
            .toolbar {
            if horizontalSizeClass == .regular, let selection {
                ToolbarItem(placement: .topBarLeading) {
                    TabMenuButton(selection: selection)
                }
            }
        }
    }
}

extension View {
    /// Adds the section menu to the leading corner of a section's root screen when the screen is wide.
    func tabMenuToolbar() -> some View {
        modifier(TabMenuToolbar())
    }
}

#Preview {
    ContentView(selectedTab: .constant(1), pendingRoundID: .constant(nil), pendingNewRound: .constant(false))
        .environment(RoundStore())
        .environment(CourseStore())
        .environment(AuthStore())
        .environment(SocialStore())
}
