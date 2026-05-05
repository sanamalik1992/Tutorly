import SwiftUI
import StoreKit

struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var storeKit = StoreKitManager.shared
    @State private var pro = ProService.shared

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
                        benefitsList
                        productButtons
                        if let err = storeKit.purchaseError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        restoreButton
                        legalFooter
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .overlay { if pro.isPro { alreadyProOverlay } }
        .task { if storeKit.products.isEmpty { await storeKit.loadProducts() } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Text("✨").font(.system(size: 48))
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

    // MARK: - Benefits list

    private var benefitsList: some View {
        VStack(spacing: 0) {
            benefit(icon: "timer", text: "Longer, uninterrupted learning sessions")
            Divider().background(Theme.hairline).padding(.leading, 52)
            benefit(icon: "calendar", text: "Learn more every day — no hard limits holding you back")
            Divider().background(Theme.hairline).padding(.leading, 52)
            benefit(icon: "brain.head.profile", text: "Full access to Hoot with deeper, richer conversations")
            Divider().background(Theme.hairline).padding(.leading, 52)
            benefit(icon: "sparkles", text: "Cancel anytime — no commitment required")
        }
        .padding(.vertical, 4)
        .background(Theme.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func benefit(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Product buttons (StoreKit)

    private var productButtons: some View {
        VStack(spacing: 10) {
            if storeKit.isLoading && storeKit.products.isEmpty {
                ProgressView().tint(Theme.ink).frame(height: 110)
            } else if storeKit.products.isEmpty {
                VStack(spacing: 12) {
                    Text("Subscription options are being set up — check back soon.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Retry") { Task { await storeKit.loadProducts() } }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                if let annual = storeKit.annual {
                    productButton(annual, primary: true, savings: savingsLabel)
                }
                if let monthly = storeKit.monthly {
                    productButton(monthly, primary: false, savings: nil)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func productButton(_ product: Product, primary: Bool, savings: String?) -> some View {
        Button {
            Task { await storeKit.purchase(product) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        if let savings {
                            Text(savings)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(primary ? .white.opacity(0.2) : Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    if let trial = product.freeTrialLabel {
                        Text("Includes \(trial)")
                            .font(.system(size: 12))
                            .foregroundStyle(primary ? .white.opacity(0.85) : Theme.inkSoft)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(primary ? .white : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 64)
            .background(primary ? Theme.accent : Theme.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(primary ? Color.clear : Theme.hairlineStrong, lineWidth: 1)
            )
        }
        .disabled(storeKit.purchaseInProgress)
        .opacity(storeKit.purchaseInProgress ? 0.6 : 1.0)
    }

    private var savingsLabel: String? {
        guard let monthly = storeKit.monthly, let annual = storeKit.annual else { return nil }
        let m = (monthly.price as NSDecimalNumber).doubleValue
        let a = (annual.price as NSDecimalNumber).doubleValue
        guard m > 0, a > 0 else { return nil }
        let yearlyAtMonthlyRate = m * 12
        guard yearlyAtMonthlyRate > a else { return nil }
        let pct = Int(((yearlyAtMonthlyRate - a) / yearlyAtMonthlyRate * 100).rounded())
        return "Save \(pct)%"
    }

    // MARK: - Restore + legal

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await storeKit.restore() }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Theme.inkSoft)
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Terms",   destination: URL(string: "https://tutorly-backend-omega.vercel.app/terms")!)
                Link("Privacy", destination: URL(string: "https://tutorly-backend-omega.vercel.app/privacy")!)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 24)
    }

    private var alreadyProOverlay: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("✨").font(.system(size: 60))
                Text("You're already Pro!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("You have full access to longer sessions and unlimited daily learning.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
