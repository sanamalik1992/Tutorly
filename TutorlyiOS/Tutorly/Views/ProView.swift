import SwiftUI

struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pro = ProService.shared
    @State private var selectedPlan: Plan = .annual

    enum Plan { case monthly, annual }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
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
                        hero
                        comparisonTable
                        planSelector
                        ctaButtons
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .overlay { if pro.isPro { alreadyProOverlay } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Text("✨")
                .font(.system(size: 48))
            Text("Tutorly Pro")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Longer sessions, more daily learning time, and full access to Hoot.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 20)
    }

    // MARK: - Comparison table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Spacer().frame(width: 110)
                colHeader("Free")
                colHeader("Trial", subtitle: "7 days")
                colHeader("Pro", highlight: true)
            }
            .padding(.vertical, 12)

            Divider().background(Theme.hairline)

            row(label: "Sessions/day", values: ["1", "3", "5"])
            row(label: "Mins/session", values: ["5", "5", "20"])
            row(label: "Daily total",  values: ["5 min", "15 min", "1h 40m"])
            row(label: "Price",        values: ["—", "—", "£7.99/mo"], last: true)
        }
        .padding(.vertical, 4)
        .background(Theme.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func colHeader(_ title: String, subtitle: String? = nil, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlight ? Theme.accent : Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(label: String, values: [String], last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 110, alignment: .leading)
                    .padding(.leading, 16)
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    Text(value)
                        .font(.system(size: 13, weight: idx == 2 ? .semibold : .regular))
                        .foregroundStyle(idx == 2 ? Theme.ink : Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            if !last { Divider().background(Theme.hairline).padding(.leading, 16) }
        }
    }

    // MARK: - Plan selector (Monthly / Annual)

    private var planSelector: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                planCard(plan: .monthly, price: "£7.99", period: "/ month", badge: nil)
                planCard(plan: .annual,  price: "£59.99", period: "/ year",  badge: "Save 37%")
            }
        }
        .padding(.horizontal, 20)
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
                    .strokeBorder(selectedPlan == plan ? Theme.accent : Theme.hairline,
                                  lineWidth: selectedPlan == plan ? 1.5 : 1)
            )
        }
    }

    // MARK: - CTA

    private var ctaButtons: some View {
        VStack(spacing: 10) {
            Button(action: { pro.startFreeTrial() }) {
                Text("Start 7-day Free Trial")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(action: { pro.openStripeCheckout(plan: selectedPlan == .annual ? .annual : .monthly) }) {
                Text("Subscribe \(selectedPlan == .annual ? "Yearly" : "Monthly")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.bgElev)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            }

            Text("Trial converts to paid after 7 days. Cancel any time.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private var alreadyProOverlay: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("✨").font(.system(size: 60))
                Text("You're already Pro!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Enjoy 5 sessions/day, 20 minutes each.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
