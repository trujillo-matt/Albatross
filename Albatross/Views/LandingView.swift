import SwiftUI

struct LandingView: View {
    @Binding var isShowing: Bool

    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.92
    @State private var taglineOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.accentColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("ALBATROSS")
                    .font(.custom("Baskerville", size: 32))
                    .foregroundStyle(.white)
                    .tracking(2)

                Image("black-browed-albatross")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .padding(.top, 12)

                Text("Est. 2026")
                    .font(.custom("Baskerville", size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .tracking(3)
                    .padding(.top, 16)
                    .opacity(taglineOpacity)

                Spacer()
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                logoOpacity = 1
                logoScale = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                taglineOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeIn(duration: 0.4)) {
                    isShowing = false
                }
            }
        }
    }
}

#Preview {
    LandingView(isShowing: .constant(true))
}
