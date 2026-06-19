import StoreKit
import SwiftUI

@Observable
final class PremiumManager {
    static let shared = PremiumManager()

    var isPremium: Bool = UserDefaults.standard.bool(forKey: "isPremium") {
        didSet { UserDefaults.standard.set(isPremium, forKey: "isPremium") }
    }
    var watermarkDisabled: Bool = UserDefaults.standard.bool(forKey: "watermarkDisabled") {
        didSet { UserDefaults.standard.set(watermarkDisabled, forKey: "watermarkDisabled") }
    }

    private(set) var products: [Product] = []
    var isPurchasing = false
    var purchaseError: String? = nil

    static let monthlyID  = "com.pola.premium.monthly"
    static let yearlyID   = "com.pola.premium.yearly"
    static let lifetimeID = "com.pola.premium.lifetime"

    private init() {
        Task { @MainActor in
            await PremiumManager.shared.startTransactionListener()
            await PremiumManager.shared.loadProducts()
            await PremiumManager.shared.refreshPurchaseStatus()
        }
    }

    @MainActor
    private func startTransactionListener() async {
        Task { @MainActor in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                if Self.productIDs.contains(tx.productID) {
                    if tx.revocationDate != nil {
                        await refreshPurchaseStatus()
                    } else {
                        isPremium = true
                    }
                    await tx.finish()
                }
            }
        }
    }

    @MainActor
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted {
                (Self.productOrder.firstIndex(of: $0.id) ?? 99) < (Self.productOrder.firstIndex(of: $1.id) ?? 99)
            }
        } catch {}
    }

    @MainActor
    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let tx) = verification {
                isPremium = true
                await tx.finish()
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        isPurchasing = false
    }

    @MainActor
    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
        isPurchasing = false
    }

    @MainActor
    func refreshPurchaseStatus() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if Self.productIDs.contains(tx.productID) {
                hasActive = true
                break
            }
        }
        isPremium = hasActive
    }

    private static let productIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]
    private static let productOrder = [monthlyID, yearlyID, lifetimeID]
}
