import Foundation
import StoreKit

@Observable
final class StoreKitManager {
    static let shared = StoreKitManager()

    // Configure these in App Store Connect (and the bundled .storekit file for local testing).
    static let monthlyID = "com.tutorly.pro.monthly"
    static let annualID  = "com.tutorly.pro.annual"
    static var productIDs: [String] { [monthlyID, annualID] }

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var purchaseInProgress = false
    private(set) var isInTrial = false
    private(set) var trialDaysRemaining: Int = 0
    var purchaseError: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var isSubscribed: Bool { !purchasedProductIDs.isEmpty }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var annual:  Product? { products.first { $0.id == Self.annualID  } }

    init() {
        updatesTask = Task { [weak self] in await self?.listenForTransactionUpdates() }
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Sort so monthly comes before annual
            self.products = loaded.sorted { ($0.price as NSDecimalNumber).doubleValue < ($1.price as NSDecimalNumber).doubleValue }
        } catch {
            print("[StoreKit] product load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseError = nil
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let txn = try checkVerified(verification)
                await txn.finish()
                purchasedProductIDs.insert(txn.productID)
                await reportToBackend(txn)
                // Sync backend Pro flag so SettingsSheet / session limits update immediately
                _ = await AuthService.shared.refreshUser()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending — waiting for approval (Ask to Buy / SCA)."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            print("[StoreKit] purchase failed: \(error)")
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            _ = await AuthService.shared.refreshUser()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements / transactions

    private func refreshEntitlements() async {
        var ids = Set<String>()
        var inTrial = false
        var daysLeft = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            guard txn.revocationDate == nil else { continue }
            ids.insert(txn.productID)
            if txn.offerType == .introductoryOffer, let expiry = txn.expirationDate {
                inTrial = true
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                daysLeft = max(0, days)
            }
        }
        purchasedProductIDs = ids
        isInTrial = inTrial
        trialDaysRemaining = daysLeft
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let txn) = result else { continue }
            await txn.finish()
            await refreshEntitlements()
            await reportToBackend(txn)
            _ = await AuthService.shared.refreshUser()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified:
            throw NSError(domain: "StoreKit", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Transaction failed verification"])
        }
    }

    // MARK: - Backend hand-off

    /// Forwards the signed JWS representation of the transaction to the backend so the server
    /// can validate it with Apple and flip the user's tier. Backend endpoint is a stub —
    /// implement /api/iap/verify to consume `signedTransaction` and store entitlements.
    private func reportToBackend(_ txn: Transaction) async {
        guard let jwt = Keychain.appJwt() else { return }
        guard let url = URL(string: "https://tutorly-backend-omega.vercel.app/api/iap/verify") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "productID": txn.productID,
            "transactionID": String(txn.id),
            "originalTransactionID": String(txn.originalID),
            "purchaseDate": ISO8601DateFormatter().string(from: txn.purchaseDate),
            "environment": txn.environment.rawValue
        ])
        _ = try? await URLSession.shared.data(for: req)
        print("[StoreKit] reported transaction \(txn.id) to backend")
    }
}

extension Product {
    /// True if this product has a "first-time subscriber" intro offer (typically a free trial).
    var hasFreeTrial: Bool {
        guard let offer = subscription?.introductoryOffer else { return false }
        return offer.paymentMode == .freeTrial
    }

    /// Human-readable trial length, e.g. "7-day free trial".
    var freeTrialLabel: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let value = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day:   unit = value == 1 ? "day"   : "days"
        case .week:  unit = value == 1 ? "week"  : "weeks"
        case .month: unit = value == 1 ? "month" : "months"
        case .year:  unit = value == 1 ? "year"  : "years"
        @unknown default: unit = "days"
        }
        return "\(value)-\(unit) free trial"
    }
}
