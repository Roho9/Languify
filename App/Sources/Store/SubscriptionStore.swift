import Foundation
import LanguifyKit
import Observation
import StoreKit

/// StoreKit 2 subscriptions. Prices always come from the App Store
/// (`Product.displayPrice`); nothing is hard-coded. Entitlement is computed
/// from verified transactions on device and confirmed server-side so the
/// backend can enforce Premium quotas.
@Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var tier: PlanTier = .free
    private(set) var activeProductID: String?
    private(set) var expiresAt: Date?
    private(set) var isPurchasing = false
    private(set) var loadError: String?
    var purchaseError: String?

    private(set) var catalog: PlanCatalog = .fallback
    private let api: LanguifyAPIClient
    private var updatesTask: Task<Void, Never>?

    init(api: LanguifyAPIClient) {
        self.api = api
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    var resolver: EntitlementResolver { EntitlementResolver(catalog: catalog, tier: tier) }

    func load() async {
        if let remote = try? await api.fetchCatalog() { catalog = remote }
        do {
            products = try await Product.products(for: catalog.premiumProductIds)
                .sorted { ($0.subscription?.subscriptionPeriod.unit == .year ? 1 : 0) < ($1.subscription?.subscriptionPeriod.unit == .year ? 1 : 0) }
            loadError = products.isEmpty ? "Subscriptions aren't available right now." : nil
        } catch {
            loadError = "Couldn't load subscription options."
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified):
                purchaseError = "The purchase couldn't be verified."
            case .pending:
                purchaseError = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "The purchase didn't complete."
            Log.store.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Couldn't restore purchases."
        }
        await refreshEntitlements()
    }

    /// Recomputes the tier from current entitlements and confirms with the backend.
    func refreshEntitlements() async {
        var best: Transaction?
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  catalog.premiumProductIds.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            signed.append(result.jwsRepresentation)
            if best == nil || (transaction.expirationDate ?? .distantFuture) > (best?.expirationDate ?? .distantPast) {
                best = transaction
            }
        }
        tier = best == nil ? .free : .premium
        activeProductID = best?.productID
        expiresAt = best?.expirationDate

        // Server confirmation. Failure here does not downgrade the local tier;
        // the backend re-checks on its next request.
        if !signed.isEmpty {
            _ = try? await api.verifyEntitlements(EntitlementRequest(signedTransactions: signed))
        }
    }
}
