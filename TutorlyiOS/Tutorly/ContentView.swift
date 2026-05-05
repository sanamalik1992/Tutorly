import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showProSheet = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Text("Tutorly").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Central orb area
                VStack(spacing: 16) {
                    Spacer()

                    Button(action: orbTapped) {
                        VoiceOrb(state: session.realtime.voiceState, size: 160)
                    }
                    .buttonStyle(.plain)

                    Text(statusLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Transcript
                transcriptArea

                Spacer(minLength: 12)

                // Pro banner
                proBanner
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }

            if let toast { toastView(toast) }
        }
        .onAppear {
            session.autoConnect()
            Task { await AuthService.shared.refreshUser() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Clean disconnect so audio engine and socket are fully torn down.
                // autoConnect on .active will rebuild everything fresh.
                session.disconnect()
            case .active:
                Task { await AuthService.shared.refreshUser() }
                session.autoConnect()
            default:
                break
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showProSheet) { ProView() }
        .onChange(of: session.realtime.errorMessage) { _, newValue in
            guard let newValue else { return }
            withAnimation { toast = newValue }
            session.realtime.errorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { toast = nil } }
        }
    }

    // MARK: - Subviews

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.transcriptTurns) { turn in
                        TranscriptBubble(turn: turn)
                            .id(turn.id)
                    }
                    if !session.realtime.liveCaption.isEmpty {
                        TranscriptBubble(turn: TranscriptTurn(role: "assistant", text: session.realtime.liveCaption))
                            .opacity(0.6)
                            .id("live")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
            .onChange(of: session.transcriptTurns.count) { _, _ in
                if let last = session.transcriptTurns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: session.realtime.liveCaption) { _, _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var proBanner: some View {
        if ProService.shared.isPro {
            Label("Tutorly Pro — Active", systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        } else {
            Button(action: { showProSheet = true }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Upgrade to Pro")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func orbTapped() {
        if session.realtime.isConnected {
            if session.realtime.voiceState == .speaking || session.realtime.isThinking {
                session.cancelResponse()   // interrupt mid-response
            } else {
                session.realtime.toggleMute()
            }
        } else {
            session.connect()
        }
    }

    private var statusLabel: String {
        guard session.realtime.isConnected else { return "Connecting…" }
        if session.realtime.isMuted { return "Muted — tap to unmute" }
        if session.realtime.voiceState == .speaking { return "Speaking — tap to interrupt" }
        if session.realtime.isThinking { return "Thinking… tap to cancel" }
        return "Listening…"
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.85), in: Capsule())
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 18)
    }
}

private struct TranscriptBubble: View {
    let turn: TranscriptTurn

    var body: some View {
        HStack {
            if turn.role == "user" { Spacer(minLength: 48) }
            Text(turn.text)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(turn.role == "user" ? Theme.accent.opacity(0.18) : Color.white.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 12))
            if turn.role != "user" { Spacer(minLength: 48) }
        }
    }
}
