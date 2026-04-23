import SwiftUI

struct VoiceDock: View {
    @Environment(TutorSession.self) private var session
    let onPause: () -> Void
    let onHint: () -> Void
    let onText: () -> Void
    let onSave: () -> Void

    @GestureState private var isPressing = false

    var body: some View {
        HStack(spacing: 10) {
            dockButton(icon: "pause.fill",      label: "pause",  action: onPause)
            dockButton(icon: "lightbulb.fill",  label: "hint",   action: onHint)

            VStack(spacing: 6) {
                VoiceOrb(state: session.realtime.voiceState, size: 88)
                    .scaleEffect(isPressing ? 1.05 : 1.0)
                    .frame(width: 110, height: 110)
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
                    .font(.ui(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)

            dockButton(icon: "text.alignleft", label: "text",   action: onText)
            dockButton(icon: "bookmark.fill",  label: "save",   action: onSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 120)
        .background(Theme.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
    }

    private var statusLabel: String {
        switch session.realtime.voiceState {
        case .speaking:  return "HOOT IS SPEAKING"
        case .listening: return "LISTENING…"
        case .idle:      return session.realtime.isConnected ? "HOLD ORB TO TALK" : "NOT CONNECTED"
        }
    }

    private func dockButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.inkSoft)
                Text(label)
                    .font(.ui(10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(width: 52, height: 52)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
