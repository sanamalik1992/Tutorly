import SwiftUI

struct AIConsentView: View {
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Owl — same asset as LoginView
                    Image("Hoot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .padding(.top, 52)
                        .padding(.bottom, 20)

                    // Title
                    Text("Before we begin")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 28)

                    // Disclosure card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tutorly uses OpenAI's Realtime API to power voice tutoring with Hoot.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)

                        Text("When you start a session:")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)

                        VStack(alignment: .leading, spacing: 10) {
                            bullet("Your voice audio is sent in real time to OpenAI's servers for AI processing")
                            bullet("OpenAI generates Hoot's spoken responses based on your questions")
                            bullet("Voice data is processed in real time — neither Tutorly nor OpenAI permanently store recordings")
                        }

                        Text("By continuing, you agree to share your voice with OpenAI for this purpose. You can read more in our Privacy Policy.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(20)
                    .background(Theme.bgElev, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            if let url = URL(string: "https://tutorly-backend-omega.vercel.app/privacy") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Read Privacy Policy")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Theme.bgElev, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Read Privacy Policy")

                        Button {
                            aiConsentGiven = true
                        } label: {
                            Text("Agree & Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Agree to data sharing and continue to Tutorly")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 52)
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
