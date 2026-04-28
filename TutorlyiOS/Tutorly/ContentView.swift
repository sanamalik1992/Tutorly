import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var auth = AuthService.shared
    @State private var showSettings = false
    @State private var showPro = false
    @GestureState private var isPressing = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Button(action: {
                        session.disconnect()
                        auth.signOut()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("End")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(Theme.inkSoft)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        if !ProService.shared.isPro {
                            Button(action: { showPro = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("Pro")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.accentSoft)
                                .clipShape(Capsule())
                            }
                        }

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer()

                // Central orb
                VStack(spacing: 14) {
                    VoiceOrb(state: session.realtime.voiceState, size: 140)
                        .scaleEffect(isPressing ? 1.06 : 1.0)
                        .frame(width: 170, height: 170)
                        .contentShape(Circle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.0)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .updating($isPressing) { value, state, _ in
                                    switch value {
                                    case .second(true, _): state = true
                                    default: state = false
                                    }
                                }
                        )
                        .onChange(of: isPressing) { _, newVal in
                            if newVal { session.realtime.startTalking() }
                            else      { session.realtime.stopTalking()  }
                        }

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)
                        .animation(.easeInOut(duration: 0.2), value: statusLabel)
                }

                Spacer()

                // Transcript
                transcriptArea
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // Bottom action row
                HStack(spacing: 20) {
                    actionButton(icon: "lightbulb", label: "Hint", action: {})
                    Spacer()
                    actionButton(icon: "bookmark", label: "Save", action: {})
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showPro) { ProView() }
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

    private var statusLabel: String {
        switch session.realtime.voiceState {
        case .speaking:  return "Hoot is speaking"
        case .listening: return "Listening…"
        case .idle:      return session.realtime.isConnected ? "Hold orb to talk" : "Not connected"
        }
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.transcriptTurns) { turn in
                        Text(turn.text)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Theme.bgElev)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if !session.realtime.liveCaption.isEmpty {
                        Text(session.realtime.liveCaption)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Theme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .id("live")
                    }
                    if session.transcriptTurns.isEmpty && session.realtime.liveCaption.isEmpty {
                        Text(session.realtime.isConnected ? "Hoot is ready — hold the orb and ask anything." : "Connecting…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxHeight: 220)
            .onChange(of: session.realtime.liveCaption) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.inkSoft)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }
}
