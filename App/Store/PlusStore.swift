import Foundation
import Observation
import StoreKit

/// Word Bubbles+, a one-time purchase that opens every day in the archive. The last week is always free.
///
/// The unlock is remembered in `UserDefaults` so the archive opens at launch before StoreKit answers, and StoreKit's
/// current entitlements correct it either way (a refund takes it back, a purchase on another device grants it).
@MainActor
@Observable
final class PlusStore {
    static let productID = "com.blopit.BBL.plus"
    static let cacheKey = "wordbubbles-plus"

    enum Status: Equatable {
        case idle
        case working
        /// Waiting on someone else, such as Ask to Buy.
        case pending
        case failed(String)
    }

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var status = Status.idle

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isUnlocked = defaults.bool(forKey: Self.cacheKey)
    }

    /// The price as the App Store shows it, once the product has loaded.
    var price: String? { product?.displayPrice }

    /// Listens for transactions made elsewhere (another device, Ask to Buy, a refund), then loads the product.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProduct()
            await refresh()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// Reads what this Apple Account owns. Works offline from StoreKit's own cache.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    func purchase() async {
        await loadProduct()
        guard let product else {
            status = .failed("The App Store isn't reachable right now. Try again in a moment.")
            return
        }
        status = .working
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                setUnlocked(true)
                status = .idle
            case .success(.unverified):
                status = .failed("The App Store couldn't confirm the purchase.")
            case .pending:
                status = .pending
            case .userCancelled:
                status = .idle
            @unknown default:
                status = .idle
            }
        } catch {
            status = .failed("The purchase didn't go through. Try again.")
        }
    }

    /// Asks the App Store for this account's purchases. It may ask the player to sign in.
    func restore() async {
        status = .working
        try? await AppStore.sync()
        await refresh()
        status = isUnlocked ? .idle : .failed("This Apple Account hasn't bought Word Bubbles+.")
    }

    private func setUnlocked(_ unlocked: Bool) {
        isUnlocked = unlocked
        defaults.set(unlocked, forKey: Self.cacheKey)
    }
}
