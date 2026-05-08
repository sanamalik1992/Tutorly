import SwiftUI

@main
struct TutorlyApp: App {
    @State private var session = TutorSession()
    @State private var auth = AuthService.shared
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    if aiConsentGiven {
                        ContentView()
                            .environment(session)
                    } else {
                        AIConsentView()
                    }
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
