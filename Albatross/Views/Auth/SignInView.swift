import SwiftUI

struct SignInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AuthStore.self) private var authStore

    /// Lets someone use the app with no account. Their rounds stay on the phone.
    var onContinueWithoutAccount: () -> Void = {}

    @State private var isSignUp = false
    @State private var firstName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool {
        let baseValid = !email.isEmpty && password.count >= 6
        if isSignUp {
            return baseValid && !firstName.isEmpty && !username.isEmpty
        }
        return baseValid
    }

    var body: some View {
        ZStack {
            Color.brandGreen
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // ── Logo + wordmark ──────────────────────────────────
                    VStack(spacing: 16) {
                        Image("black-browed-albatross")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 68)

                        Text("ALBATROSS")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                            .kerning(8)

                        Text("Track every round.")
                            .appFont(.small)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 72)
                    .padding(.bottom, 48)

                    // ── Form fields ──────────────────────────────────────
                    VStack(spacing: 12) {
                        if isSignUp {
                            inputField(
                                icon: "person",
                                placeholder: "First name",
                                text: $firstName,
                                keyboard: .default,
                                capitalization: .words,
                                secure: false
                            )
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

                            inputField(
                                icon: "at",
                                placeholder: "Username",
                                text: $username,
                                keyboard: .asciiCapable,
                                capitalization: .never,
                                secure: false
                            )
                            .onChange(of: username) { _, val in
                                // Force lowercase, strip spaces
                                let cleaned = val.lowercased().filter { !$0.isWhitespace }
                                if cleaned != val { username = cleaned }
                            }
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }

                        inputField(
                            icon: "envelope",
                            placeholder: "Email",
                            text: $email,
                            keyboard: .emailAddress,
                            capitalization: .never,
                            secure: false
                        )

                        inputField(
                            icon: "lock",
                            placeholder: isSignUp ? "Password (min. 6 characters)" : "Password",
                            text: $password,
                            keyboard: .default,
                            capitalization: .never,
                            secure: true
                        )

                        // Error message
                        if let error = authStore.errorMessage {
                            Text(error)
                                .appFont(.small)
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                                .transition(.opacity)
                        }

                        // Primary action button
                        Button(action: submit) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white)
                                    .frame(height: 54)

                                if authStore.isLoading {
                                    ProgressView()
                                        .tint(Color.brandGreen)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .appFont(.body, weight: .semibold)
                                        .foregroundStyle(Color.brandGreen)
                                }
                            }
                        }
                        .disabled(!canSubmit || authStore.isLoading)
                        .opacity(canSubmit && !authStore.isLoading ? 1.0 : 0.5)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.2), value: isSignUp)

                    // ── Toggle sign-in / sign-up ─────────────────────────
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            authStore.errorMessage = nil
                        }
                    }) {
                        Group {
                            if isSignUp {
                                Text("Already have an account? **Sign in**")
                            } else {
                                Text("Don't have an account? **Create one**")
                            }
                        }
                        .appFont(.small)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.pressFeedback)
                    .padding(.top, 24)

                    VStack(spacing: 4) {
                        Button(action: onContinueWithoutAccount) {
                            Text("Continue without an account")
                                .appFont(.small, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressFeedback)

                        Text("Your rounds stay on this phone. Sign in later to sync and see friends.")
                            .appFont(.small)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 12)

                    Text("By continuing you agree to our\nTerms of Service and Privacy Policy.")
                        .appFont(.small)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.bottom, 48)
                }
                .readableContentWidth(480)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeInOut(duration: 0.15), value: authStore.errorMessage == nil)
    }

    // MARK: - Input field

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        capitalization: TextInputAutocapitalization,
        secure: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .appFont(.body, weight: .medium)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)

            if secure {
                SecureField(placeholder, text: text)
                    .appFont(.body)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .appFont(.body)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    // MARK: - Submit

    private func submit() {
        Task {
            if isSignUp {
                await authStore.signUp(
                    email: email,
                    password: password,
                    firstName: firstName,
                    username: username
                )
            } else {
                await authStore.signIn(email: email, password: password)
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthStore())
}
