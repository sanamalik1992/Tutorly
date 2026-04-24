import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 12)
                TopNav(onClose: { session.disconnect() }, onMore: { showSettings = true })
                    .padding(.horizontal, 16)
                Spacer().frame(height: 16)
                Whiteboard()
                    .padding(.horizontal, 16)
                Spacer()
                LiveCaption(text: session.realtime.liveCaption)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                VoiceDock(
                    onPause: { },
                    onHint:  { },
                    onText:  { },
                    onSave:  { }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .alert("Error", isPresented: Binding(
            get: { session.realtime.errorMessage != nil },
            set: { if !$0 { session.realtime.errorMessage = nil } }
        )) {
            Button("OK") { session.realtime.errorMessage = nil }
        } message: {
            Text(session.realtime.errorMessage ?? "")
        }
        .task {
            if Keychain.read("openai") != nil, !session.realtime.isConnected {
                session.connect()
            } else if Keychain.read("openai") == nil {
                showSettings = true
            }
        }
    }
}
