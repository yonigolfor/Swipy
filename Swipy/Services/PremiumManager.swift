import StoreKit
import SwiftUI

@MainActor
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    // Set this product ID in App Store Connect as a Non-Consumable or Auto-Renewable Subscription.
    static let productID = "com.yonigolfor.Swipy.monthlySubscription"

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var product: Product? = nil
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProduct()
            await updatePremiumStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProduct() async {
        do {
            let fetched = try await Product.products(for: [PremiumManager.productID])
            product = fetched.first
        } catch {
            print("[PremiumManager] Failed to load product: \(error)")
        }
    }

    func purchase() async {
        guard let product else { return }
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
        var hasPremium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == PremiumManager.productID,
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                hasPremium = true
                break
            }
        }
        isPremium = hasPremium
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
