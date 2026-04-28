import SwiftUI

struct WelcomeSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("🎧")
                    .font(.system(size: 72))

                Text("Welcome to Tutorly")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: 12) {
                    Text("Your AI voice tutor")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text("Hold the coral orb, ask any question, and Hoot will explain it back to you.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 8) {
                    Text("Best with headphones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("On phone speaker, the tutor may occasionally interrupt itself due to echo.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Theme.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(.horizontal, 32)

                Spacer()

                Button(action: onDismiss) {
                    Text("Let's start")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
