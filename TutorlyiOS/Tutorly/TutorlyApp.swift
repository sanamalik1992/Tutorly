import SwiftUI

@main
struct TutorlyApp: App {
    @State private var session = TutorSession()
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    ContentView()
                        .environment(session)
                } else {
                    LoginView()
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in ProService.shared.handleDeepLink(url) }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if isSignedIn { session.autoConnect() }
            }
        }
    }
}
