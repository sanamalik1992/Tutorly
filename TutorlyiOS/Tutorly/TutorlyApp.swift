import SwiftUI

@main
struct TutorlyApp: App {
    @State private var session = TutorSession()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(session).preferredColorScheme(.dark)
        }
    }
}
