import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @State private var auth = AuthService.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Theme.accent)

                    Text("Tutorly")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)

                    Text("Your AI tutor, ready when you are")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 16) {
                    if auth.isLoading {
                        ProgressView()
                            .tint(Theme.ink)
                            .frame(height: 56)
                    } else {
                        SignInWithAppleButton(.signIn, onRequest: { req in
                            req.requestedScopes = [.fullName, .email]
                        }, onCompletion: { result in
                            handleAppleResult(result)
                        })
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if let err = auth.authError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
                .animation(.easeInOut, value: auth.isLoading)
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                AuthService.shared.authError = "Sign in failed — try again"
                return
            }
            let parts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
            let fullName: String? = parts.isEmpty ? nil : parts.joined(separator: " ")
            Task { await AuthService.shared.signInWithApple(identityToken: token, fullName: fullName) }
        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.code != ASAuthorizationError.canceled.rawValue {
                AuthService.shared.authError = error.localizedDescription
            }
        }
    }
}
