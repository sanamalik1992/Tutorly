import Foundation
import UIKit

@Observable
final class ProService {
    static let shared = ProService()

    // Replace with your Stripe backend endpoint that creates a Checkout Session
    // and returns a redirect to Stripe's hosted checkout page.
    static let checkoutURL = "https://your-backend.com/checkout?plan=pro_monthly"

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

    func openStripeCheckout() {
        guard let url = URL(string: Self.checkoutURL) else { return }
        UIApplication.shared.open(url, options: [:])
    }

    // Call from TutorlyApp.onOpenURL
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "tutorly" else { return }
        if url.host == "pro-success" {
            activatePro()
        }
    }
}
