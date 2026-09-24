import StoreKit
import SwiftUI

@Observable
final class PremiumManager {
    static let shared = PremiumManager()

    var isPremium: Bool = UserDefaults.standard.bool(forKey: "isPremium") {
        didSet { UserDefaults.standard.set(isPremium, forKey: "isPremium") }
    }
    // Opt-in: premium exports are clean by default, this brings the logo back.
    var showLogoOnExports: Bool = UserDefaults.standard.bool(forKey: "showLogoOnExports") {
        didSet { UserDefaults.standard.set(showLogoOnExports, forKey: "showLogoOnExports") }
    }

    var shouldWatermarkExports: Bool { !isPremium || showLogoOnExports }

    private(set) var products: [Product] = []
    private(set) var activeProductID: String? = nil
    private(set) var expirationDate: Date? = nil
    private(set) var willAutoRenew = false
    var isPurchasing = false
    var purchaseError: String? = nil

    static let monthlyID  = "com.pola.premium.monthly"
    static let yearlyID   = "com.pola.premium.yearly"
    static let lifetimeID = "com.pola.premium.lifetime"

    var isSubscriber: Bool {
        activeProductID == Self.monthlyID || activeProductID == Self.yearlyID
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeID }
    }

    var activePlanName: String? {
        activeProductID.flatMap(Self.planName(for:))
    }

    /// Plan names come from the app's own strings so they're translated even when a
    /// storefront is missing a localization in App Store Connect.
    static func planName(for productID: String) -> String? {
        switch productID {
        case monthlyID:  return NSLocalizedString("Monthly", comment: "")
        case yearlyID:   return NSLocalizedString("Yearly", comment: "")
        case lifetimeID: return NSLocalizedString("Lifetime", comment: "")
        default: return nil
        }
    }

    private init() {
        Task { @MainActor in
            await PremiumManager.shared.startTransactionListener()
            await PremiumManager.shared.loadProducts()
            await PremiumManager.shared.refreshPurchaseStatus()
        }
    }

    private func startTransactionListener() async {
        Task { @MainActor in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                guard Self.productIDs.contains(tx.productID) else { continue }
                await tx.finish()
                // Updates also arrive for expirations and refunds, so re-derive state instead of assuming "unlocked".
                await refreshPurchaseStatus()
            }
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted {
                (Self.productOrder.firstIndex(of: $0.id) ?? 99) < (Self.productOrder.firstIndex(of: $1.id) ?? 99)
            }
        } catch {}
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        Analytics.track(.purchaseStarted, ["product": product.id])
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return false }
                await tx.finish()
                await refreshPurchaseStatus()
                Analytics.track(.purchaseCompleted, ["product": product.id])
                return true
            case .userCancelled:
                Analytics.track(.purchaseCancelled, ["product": product.id])
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            Analytics.track(.purchaseFailed, ["product": product.id])
            return false
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
            if isPremium { Analytics.track(.restoreCompleted) }
        } catch {
            purchaseError = error.localizedDescription
        }
        isPurchasing = false
    }

    func refreshPurchaseStatus() async {
        var bestTx: StoreKit.Transaction? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  Self.productIDs.contains(tx.productID) else { continue }
            // Lifetime wins over any subscription so we never show a renewal date to lifetime owners.
            if tx.productID == Self.lifetimeID {
                bestTx = tx
                break
            }
            if bestTx == nil || (tx.expirationDate ?? .distantPast) > (bestTx?.expirationDate ?? .distantPast) {
                bestTx = tx
            }
        }

        activeProductID = bestTx?.productID
        expirationDate = bestTx?.expirationDate
        willAutoRenew = false
        if let bestTx, bestTx.productID != Self.lifetimeID,
           let status = await bestTx.subscriptionStatus,
           case .verified(let renewal) = status.renewalInfo {
            willAutoRenew = renewal.willAutoRenew
        }
        isPremium = bestTx != nil
    }

    private static let productIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]
    private static let productOrder = [monthlyID, yearlyID, lifetimeID]
}

// MARK: - Pricing display helpers

extension Product {
    /// The free-trial part of the introductory offer, if the offer is a free trial.
    var freeTrialPeriod: Product.SubscriptionPeriod? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return offer.period
    }

    /// "7 days", "1 month" — used in trial badges and the post-trial disclosure.
    var freeTrialText: String? {
        guard let period = freeTrialPeriod else { return nil }
        let (count, one, many): (Int, String, String)
        switch period.unit {
        case .day:   (count, one, many) = (period.value, "1 day", "%d days")
        case .week:  (count, one, many) = (period.value * 7, "1 day", "%d days")
        case .month: (count, one, many) = (period.value, "1 month", "%d months")
        case .year:  (count, one, many) = (period.value, "1 year", "%d years")
        @unknown default: return nil
        }
        return count == 1
            ? NSLocalizedString(one, comment: "")
            : String(format: NSLocalizedString(many, comment: ""), count)
    }

    /// "$19.99/year", "$2.99/month"; the plain price for non-subscriptions.
    var pricePerPeriodText: String {
        guard let unit = subscription?.subscriptionPeriod.unit else { return displayPrice }
        let format: String
        switch unit {
        case .year:  format = NSLocalizedString("%@/year", comment: "")
        case .month: format = NSLocalizedString("%@/month", comment: "")
        case .week:  format = NSLocalizedString("%@/week", comment: "")
        default:     return displayPrice
        }
        return String(format: format, displayPrice)
    }

    /// Price divided by 12, formatted in the storefront currency. Only meaningful for yearly plans.
    var monthlyEquivalentText: String {
        (price / 12).formatted(priceFormatStyle)
    }
}
