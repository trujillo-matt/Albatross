import WidgetKit
import SwiftUI

@main
struct AlbatrossWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlbatrossLiveActivityWidget()
        TournamentMatchLiveActivityWidget()
        StartRoundWidget()
    }
}
