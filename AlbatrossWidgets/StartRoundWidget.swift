import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StartRoundEntry: TimelineEntry {
    let date: Date
}

struct StartRoundProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartRoundEntry { .init(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StartRoundEntry) -> Void) {
        completion(.init(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartRoundEntry>) -> Void) {
        // Content never changes — reload only when the system decides
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

// MARK: - Small widget

private struct StartRoundSmall: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("black-browed-albatross")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .opacity(0.9)
            Text("Start Round")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("ALBATROSS")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandGreen)
    }
}

// MARK: - Medium widget

private struct StartRoundMedium: View {
    var body: some View {
        HStack(spacing: 18) {
            Image("black-browed-albatross")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 4) {
                Text("Start Round")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Tap to begin scoring")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                Text("ALBATROSS")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)
                    .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "flag.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandGreen)
    }
}

// MARK: - Entry view

struct StartRoundWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StartRoundEntry

    var body: some View {
        switch family {
        case .systemMedium: StartRoundMedium()
        default:            StartRoundSmall()
        }
    }
}

// MARK: - Widget declaration

struct StartRoundWidget: Widget {
    let kind = "StartRoundWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StartRoundProvider()) { entry in
            StartRoundWidgetView(entry: entry)
                .widgetURL(URL(string: "albatross://newround"))
        }
        .configurationDisplayName("Start Round")
        .description("Tap to start a new round in Albatross.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    StartRoundWidget()
} timeline: {
    StartRoundEntry(date: .now)
}

#Preview(as: .systemMedium) {
    StartRoundWidget()
} timeline: {
    StartRoundEntry(date: .now)
}
