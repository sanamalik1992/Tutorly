import Foundation
import AuthenticationServices

@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var currentUser: TutorlyUser?
    var isSignedIn: Bool { currentUser != nil }

    init() {
        if let str = Keychain.read("tutorly.user"),
           let data = str.data(using: .utf8),
           let user = try? JSONDecoder().decode(TutorlyUser.self, from: data) {
            currentUser = user
        }
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let nameParts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
            let user = TutorlyUser(
                id: cred.user,
                name: nameParts.isEmpty ? "Student" : nameParts.joined(separator: " "),
                email: cred.email,
                isGuest: false
            )
            save(user: user)
        case .failure(let error):
            print("[Auth] Sign in with Apple error: \(error.localizedDescription)")
        }
    }

    func continueAsGuest() {
        save(user: TutorlyUser(id: UUID().uuidString, name: "Guest", email: nil, isGuest: true))
    }

    func signOut() {
        currentUser = nil
        Keychain.delete("tutorly.user")
        ProService.shared.clearPro()
    }

    private func save(user: TutorlyUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user), let str = String(data: data, encoding: .utf8) {
            Keychain.save(str, for: "tutorly.user")
        }
    }
}

struct TutorlyUser: Codable, Identifiable {
    let id: String
    let name: String
    let email: String?
    let isGuest: Bool
}
