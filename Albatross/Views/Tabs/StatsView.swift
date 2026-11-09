import SwiftUI

struct StatsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Color.accentColor)

                    Text("Stats")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Historical data coming soon")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Stats")
        }
    }
}

#Preview {
    StatsView()
}
