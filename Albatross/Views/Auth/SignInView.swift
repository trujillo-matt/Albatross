import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authStore: AuthStore

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
            Color(red: 0.141, green: 0.157, blue: 0.133)
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
                            .font(.custom("Baskerville-Bold", size: 30))
                            .foregroundStyle(.white)
                            .kerning(8)

                        Text("Track every round.")
                            .font(.custom("Baskerville", size: 15))
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
                            .transition(.move(edge: .top).combined(with: .opacity))

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
                            .transition(.move(edge: .top).combined(with: .opacity))
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
                                .font(.custom("Baskerville", size: 13))
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                                .transition(.opacity)
                        }

                        // Primary action button
                        Button(action: submit) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white)
                                    .frame(height: 54)

                                if authStore.isLoading {
                                    ProgressView()
                                        .tint(Color(red: 0.141, green: 0.208, blue: 0.153))
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.custom("Baskerville-Bold", size: 17))
                                        .foregroundStyle(Color(red: 0.141, green: 0.208, blue: 0.153))
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
                        .font(.custom("Baskerville", size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    Text("By continuing you agree to our\nTerms of Service and Privacy Policy.")
                        .font(.custom("Baskerville", size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.bottom, 48)
                }
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)

            if secure {
                SecureField(placeholder, text: text)
                    .font(.custom("Baskerville", size: 16))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .font(.custom("Baskerville", size: 16))
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
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
        .environmentObject(AuthStore())
}
