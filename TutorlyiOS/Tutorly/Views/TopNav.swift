import SwiftUI

struct TopNav: View {
    @Environment(TutorSession.self) private var session
    let onClose: () -> Void
    let onMore: () -> Void
    @State private var elapsedSeconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.bgElev)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            }

            HStack(spacing: 10) {
                PulsingDot()
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.topic)
                        .font(.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(session.realtime.isConnected ? "live · \(formattedTime)" : "connecting…")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.bgElev)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.bgElev)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
        .onReceive(timer) { _ in
            if session.realtime.isConnected { elapsedSeconds += 1 }
        }
    }

    private var formattedTime: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

struct PulsingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.2 : 1.0)
            .opacity(pulse ? 0.7 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
