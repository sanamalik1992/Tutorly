import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var showSettings = false
    @State private var toast: String?
    @GestureState private var isPressing = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Tutorly")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                VoiceOrb(state: session.realtime.voiceState, size: 140)
                    .scaleEffect(isPressing ? 1.06 : 1)
                    .gesture(
                        LongPressGesture(minimumDuration: 0)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .updating($isPressing) { value, state, _ in
                                if case .second(true, _) = value { state = true } else { state = false }
                            }
                    )
                    .onChange(of: isPressing) { _, newValue in
                        if newValue { session.realtime.startTalking() }
                        else { session.realtime.stopTalking() }
                    }

                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 12)

                Spacer()

                Button(action: connectOrMute) {
                    Text(session.realtime.isConnected ? (session.realtime.isMuted ? "Unmute" : "Mute") : "Connect")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospaced())
                        .tracking(1.2)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 30)
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: session.realtime.errorMessage) { _, msg in
            guard let msg else { return }
            toast = msg
            session.realtime.errorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { toast = nil }
        }
    }

    private var statusText: String {
        if !session.realtime.isConnected { return "Tap Connect to start" }
        if session.realtime.isMuted { return "Muted" }
        if session.realtime.voiceState == .speaking { return "Tutorly is speaking" }
        if session.realtime.isThinking { return "Tutorly is thinking" }
        return "Hold and speak"
    }

    private func connectOrMute() {
        if session.realtime.isConnected { session.realtime.toggleMute() }
        else { session.connect() }
    }
}
