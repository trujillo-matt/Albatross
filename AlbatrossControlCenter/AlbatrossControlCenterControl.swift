import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intent
//
// openAppWhenRun brings Albatross to the foreground.
// We also write a flag to the shared App Group UserDefaults so AlbatrossApp
// (watching willEnterForegroundNotification) triggers NewRoundSheet automatically.
//
// Required setup in Xcode:
//   Main app target  → Signing & Capabilities → App Groups → group.TrujSoft.Albatross
//   This target      → Signing & Capabilities → App Groups → group.TrujSoft.Albatross

struct StartRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Round"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.TrujSoft.Albatross")
        defaults?.set(true, forKey: "pendingNewRound")
        defaults?.synchronize()
        return .result()
    }
}

// MARK: - Provider

struct StartRoundControlProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { false }
}

// MARK: - Control Widget

struct AlbatrossControlCenterControl: ControlWidget {
    static let kind: String = "TrujSoft.Albatross.AlbatrossControlCenter"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: StartRoundControlProvider()
        ) { _ in
            ControlWidgetButton(action: StartRoundIntent()) {
                Label("Start Round", systemImage: "flag.fill")
            }
            .tint(Color(red: 0.141, green: 0.208, blue: 0.153))
        }
        .displayName("Start Round")
        .description("Open Albatross to begin a new round.")
    }
}
