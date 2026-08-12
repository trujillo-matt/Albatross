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
                        .font(.custom("Baskerville-Bold", size: 22))
                        .foregroundStyle(.secondary)

                    Text("Historical data coming soon")
                        .font(.custom("Baskerville", size: 15))
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
