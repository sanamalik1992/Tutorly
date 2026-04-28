import SwiftUI

struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pro = ProService.shared
    @State private var selectedPlan: Plan = .monthly

    enum Plan { case monthly, annual }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Hero
                        VStack(spacing: 12) {
                            Text("✨")
                                .font(.system(size: 48))
                            Text("Tutorly Pro")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text("Unlimited 1-on-1 sessions with your AI tutor.")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Features
                        VStack(spacing: 0) {
                            ForEach(features, id: \.self) { feature in
                                HStack(spacing: 14) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                        .font(.system(size: 18))
                                    Text(feature)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                if feature != features.last {
                                    Divider().background(Theme.hairline).padding(.leading, 52)
                                }
                            }
                        }
                        .background(Theme.bgElev)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                        .padding(.horizontal, 20)

                        // Plan selector
                        HStack(spacing: 10) {
                            planCard(plan: .monthly, price: "$9.99", period: "/ month", badge: nil)
                            planCard(plan: .annual,  price: "$59.99", period: "/ year", badge: "Save 50%")
                        }
                        .padding(.horizontal, 20)

                        // CTA
                        VStack(spacing: 10) {
                            Button(action: { pro.openStripeCheckout() }) {
                                Text("Subscribe with Stripe")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Text("Secure payment via Stripe. Cancel any time.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .overlay {
            if pro.isPro {
                alreadyProOverlay
            }
        }
    }

    private var alreadyProOverlay: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("✨")
                    .font(.system(size: 60))
                Text("You're already Pro!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Enjoy unlimited sessions with Hoot.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func planCard(plan: Plan, price: String, period: String, badge: String?) -> some View {
        Button(action: { selectedPlan = plan }) {
            VStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                } else {
                    Spacer().frame(height: 22)
                }
                Text(price)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(period)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedPlan == plan ? Theme.accentSoft : Theme.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selectedPlan == plan ? Theme.accent : Theme.hairline, lineWidth: selectedPlan == plan ? 1.5 : 1)
            )
        }
    }

    private let features = [
        "Unlimited voice sessions",
        "Extended conversation memory",
        "Priority AI response speed",
        "All subjects & topics",
        "Session history"
    ]
}
