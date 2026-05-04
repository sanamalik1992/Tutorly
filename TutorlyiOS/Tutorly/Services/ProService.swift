import Foundation

/// Thin compatibility layer kept so existing call sites (`ProService.shared.isPro`)
/// continue to work. The actual source of truth for entitlement is StoreKitManager.
@Observable
final class ProService {
    static let shared = ProService()

    private let storeKit = StoreKitManager.shared

    // True if either local StoreKit entitlement OR backend flag says Pro.
    // This keeps things working even if one source hasn't synced yet.
    var isPro: Bool {
        storeKit.isSubscribed || (AuthService.shared.currentUser?.isPro ?? false)
    }

    func handleDeepLink(_ url: URL) {
        // No-op for IAP — Apple manages purchase confirmation in-app.
        // Reserved for any other future deep links (share, etc.).
        _ = url
    }
}
