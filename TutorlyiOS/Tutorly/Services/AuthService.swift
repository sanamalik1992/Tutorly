import Foundation
import AuthenticationServices

private let backendBase = "https://tutorly-backend-omega.vercel.app"

// MARK: - Model

struct TutorlyUser: Codable, Identifiable {
    let id: String
    let name: String
    let email: String?
    var isPro: Bool
    var sessionsRemaining: Int  // -1 = unlimited (Pro)
    var secondsToday: Int
}

// MARK: - Service

@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var currentUser: TutorlyUser?
    var isSignedIn: Bool { currentUser != nil }
    var isLoading = false
    var authError: String?

    init() {
        // Restore persisted user — JWT presence is the source of truth
        if Keychain.appJwt() != nil,
           let str  = Keychain.read("tutorly.user"),
           let data = str.data(using: .utf8),
           let user = try? JSONDecoder().decode(TutorlyUser.self, from: data) {
            currentUser = user
        }
    }

    // MARK: - Sign in with Apple

    func signInWithApple(identityToken: String, fullName: String?) async {
        await MainActor.run { isLoading = true; authError = nil }
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            var body: [String: Any] = ["identityToken": identityToken]
            if let name = fullName { body["fullName"] = name }

            guard let url = URL(string: "\(backendBase)/api/auth/apple") else { return }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = parseError(data) ?? "Sign in failed (server error)"
                await MainActor.run { authError = msg }
                print("[Auth] /api/auth/apple failed: \(msg)")
                return
            }

            guard let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token  = json["token"] as? String,
                  let uDict  = json["user"]  as? [String: Any] else {
                await MainActor.run { authError = "Unexpected server response" }
                return
            }

            let user = TutorlyUser(
                id:                uDict["id"]    as? String ?? UUID().uuidString,
                name:              uDict["name"]  as? String ?? fullName ?? "Student",
                email:             uDict["email"] as? String,
                isPro:             uDict["isPro"] as? Bool   ?? false,
                sessionsRemaining: 3,
                secondsToday:      0
            )

            Keychain.saveAppJwt(token)
            persist(user)
            await MainActor.run { self.currentUser = user }
            print("[Auth] signed in id=\(user.id) isPro=\(user.isPro)")

        } catch {
            await MainActor.run { authError = error.localizedDescription }
            print("[Auth] sign-in error: \(error)")
        }
    }

    // MARK: - Refresh (called on launch to validate JWT + sync state)

    @discardableResult
    func refreshUser() async -> Bool {
        guard let jwt = Keychain.appJwt() else { return false }

        do {
            guard let url = URL(string: "\(backendBase)/api/user/me") else { return false }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return true }

            if http.statusCode == 401 {
                print("[Auth] JWT expired — signing out")
                await MainActor.run { self.signOut() }
                return false
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return true  // non-auth error, keep user signed in
            }

            var base = currentUser ?? TutorlyUser(id: "", name: "Student", email: nil,
                                                   isPro: false, sessionsRemaining: 3, secondsToday: 0)
            if let u = json["user"] as? [String: Any] {
                let usage = json["usage"] as? [String: Any]
                base = TutorlyUser(
                    id:                u["id"]    as? String ?? base.id,
                    name:              u["name"]  as? String ?? base.name,
                    email:             u["email"] as? String ?? base.email,
                    isPro:             u["isPro"] as? Bool   ?? base.isPro,
                    sessionsRemaining: usage?["sessionsRemaining"] as? Int ?? base.sessionsRemaining,
                    secondsToday:      usage?["secondsToday"]      as? Int ?? base.secondsToday
                )
            }

            persist(base)
            await MainActor.run { self.currentUser = base }
            print("[Auth] refreshed isPro=\(base.isPro) sessionsLeft=\(base.sessionsRemaining)")
            return true

        } catch {
            print("[Auth] refresh network error: \(error.localizedDescription)")
            return true  // network failure — keep signed in
        }
    }

    // MARK: - Sign out

    func signOut() {
        currentUser = nil
        Keychain.deleteAppJwt()
        Keychain.delete("tutorly.user")
        print("[Auth] signed out")
    }

    // MARK: - Private

    private func persist(_ user: TutorlyUser) {
        guard let data = try? JSONEncoder().encode(user),
              let str  = String(data: data, encoding: .utf8) else { return }
        Keychain.save(str, for: "tutorly.user")
    }

    private func parseError(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg  = json["message"] as? String else { return nil }
        return msg
    }
}
