import Foundation
import UIKit

@Observable
final class ProService {
    static let shared = ProService()

    enum Plan: String { case monthly, annual, trial }

    // Backend endpoint that creates a Stripe Checkout Session and redirects to it.
    // Append the plan name as a query param so the backend knows which Price ID to use.
    static let checkoutBase = "https://tutorly-backend-omega.vercel.app/api/checkout"

    private(set) var isPro: Bool

    init() {
        isPro = UserDefaults.standard.bool(forKey: "tutorly.isPro")
    }

    func activatePro() {
        isPro = true
        UserDefaults.standard.set(true, forKey: "tutorly.isPro")
    }

    func clearPro() {
        isPro = false
        UserDefaults.standard.set(false, forKey: "tutorly.isPro")
    }

    func openStripeCheckout(plan: Plan = .annual) {
        guard let url = URL(string: "\(Self.checkoutBase)?plan=\(plan.rawValue)") else { return }
        UIApplication.shared.open(url, options: [:])
    }

    func startFreeTrial() {
        openStripeCheckout(plan: .trial)
    }

    // Call from TutorlyApp.onOpenURL
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "tutorly" else { return }
        if url.host == "pro-success" {
            activatePro()
        }
    }
}
