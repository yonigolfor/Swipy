import StoreKit
import SwiftUI

enum PremiumTier: String, CaseIterable, Identifiable {
    case monthly, yearly, lifetime
    var id: String { rawValue }

    // Set these product IDs in App Store Connect: Monthly/Yearly as Auto-Renewable
    // Subscriptions in the same subscription group, Lifetime as a Non-Consumable.
    var productID: String {
        switch self {
        case .monthly:  return "com.yonigolfor.Swipy.monthlySubscription"
        case .yearly:   return "com.yonigolfor.Swipy.yearlySubscription"
        case .lifetime: return "com.yonigolfor.Swipy.lifetimePurchase"
        }
    }

    var displayName: String {
        switch self {
        case .monthly:  return String(localized: "paywall.tier.monthly")
        case .yearly:   return String(localized: "paywall.tier.yearly")
        case .lifetime: return String(localized: "paywall.tier.lifetime")
        }
    }

    init?(productID: String) {
        guard let match = PremiumTier.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = match
    }
}

@MainActor
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var hasActiveSubscription: Bool = false
    @Published private(set) var products: [PremiumTier: Product] = [:]
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePremiumStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: PremiumTier.allCases.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: fetched.compactMap { product in
                PremiumTier(productID: product.id).map { ($0, product) }
            })
            let missing = PremiumTier.allCases.filter { products[$0] == nil }
            if !missing.isEmpty {
                print("[PremiumManager] No StoreKit product resolved for: \(missing.map(\.productID))")
            }
        } catch {
            print("[PremiumManager] Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return }
                await transaction.finish()
                await updatePremiumStatus()
                AnalyticsService.shared.log(.subscriptionPurchased, detail: PremiumTier(productID: product.id)?.rawValue)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await updatePremiumStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePremiumStatus() async {
        let tierProductIDs = Set(PremiumTier.allCases.map(\.productID))
        var hasPremium = false
        var hasSubscription = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  tierProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }

            switch transaction.productType {
            case .autoRenewable:
                if let expirationDate = transaction.expirationDate, expirationDate > Date() {
                    hasPremium = true
                    hasSubscription = true
                }
            case .nonConsumable:
                hasPremium = true
            default:
                print("[PremiumManager] Unexpected productType \(transaction.productType) for known product \(transaction.productID)")
            }
        }
        isPremium = hasPremium
        hasActiveSubscription = hasSubscription
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.updatePremiumStatus()
                }
            }
        }
    }
}
