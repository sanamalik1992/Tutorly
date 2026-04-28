import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @State private var auth = AuthService.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 16) {
                    Text("🦉")
                        .font(.system(size: 80))
                    Text("Tutorly")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Your AI voice tutor")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer()

                // Headphones tip
                VStack(spacing: 6) {
                    Text("🎧  Best experienced with headphones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("On speaker, the AI may occasionally interrupt itself due to echo.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(Theme.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

                // Auth buttons
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn, onRequest: { req in
                        req.requestedScopes = [.fullName, .email]
                    }, onCompletion: { result in
                        auth.handleAppleResult(result)
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button(action: { auth.continueAsGuest() }) {
                        Text("Continue as Guest")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.bgElev)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}
