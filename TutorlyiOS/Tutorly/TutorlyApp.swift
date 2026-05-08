import SwiftUI

@main
struct TutorlyApp: App {
    @State private var session = TutorSession()
    @State private var auth = AuthService.shared
    @State private var proService = ProService.shared
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    if aiConsentGiven {
                        if proService.isPro {
                            ContentView()
                                .environment(session)
                        } else {
                            // Must start the free trial before entering the app.
                            // Once they subscribe, proService.isPro becomes true and
                            // SwiftUI automatically transitions to ContentView.
                            ProView(isGated: true)
                        }
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
