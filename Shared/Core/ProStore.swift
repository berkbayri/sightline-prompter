import Foundation
import StoreKit

/// One purchasable plan as the paywall shows it.
public struct ProOffer: Identifiable, Equatable {
    public enum Kind: Equatable { case yearly, monthly, lifetime }

    public let id: String
    public let kind: Kind
    public let title: String
    public let price: String
    /// "per year", "per month", "one time".
    public let period: String
    /// Free trial wording, when the user is eligible: "7 days free".
    public let trial: String?
    public let badge: String?

    public init(id: String, kind: Kind, title: String, price: String, period: String, trial: String?, badge: String?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.price = price
        self.period = period
        self.trial = trial
        self.badge = badge
    }
}

/// Sightline Pro: one subscription group (monthly, yearly) and a lifetime unlock. One purchase covers iPhone
/// and Mac, because both apps share one App Store record. Prices always come from the App Store, never from here.
@MainActor
public final class ProStore: ObservableObject {
    public static let shared = ProStore()

    public static let monthlyID = "com.berkbayri.SightlinePrompter.pro.monthly"
    public static let yearlyID = "com.berkbayri.SightlinePrompter.pro.yearly"
    public static let lifetimeID = "com.berkbayri.SightlinePrompter.pro.lifetime"
    private static let allIDs = [yearlyID, monthlyID, lifetimeID]

    /// True while a valid Pro purchase exists (subscription running, or lifetime bought).
    @Published public private(set) var isPro = false
    @Published public private(set) var offers: [ProOffer] = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var loadFailed = false
    @Published public var message: String?

    #if DEBUG || SIGHTLINE_DEV
    /// Debug and developer builds only (macOS/build.sh sets SIGHTLINE_DEV): act as if Pro were bought, to try
    /// the paid features without the App Store. Never compiled into the App Store build.
    @Published public var debugPro: Bool {
        didSet { UserDefaults.standard.set(debugPro, forKey: "debugPro") }
    }
    #endif

    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var started = false

    private init() {
        #if SIGHTLINE_DEV
        // Developer build: everything open unless switched off with `defaults write ... debugPro -bool false`.
        debugPro = UserDefaults.standard.object(forKey: "debugPro") as? Bool ?? true
        #elseif DEBUG
        debugPro = UserDefaults.standard.bool(forKey: "debugPro")
        #endif
    }

    /// Whether paid features are open. Use this everywhere, never `isPro` directly.
    public var isUnlocked: Bool {
        #if DEBUG || SIGHTLINE_DEV
        if debugPro { return true }
        #endif
        return isPro
    }

    /// Starts listening for purchases, loads prices and reads what the user already owns. Call once at launch.
    public func start() {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    public func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            loadFailed = loaded.isEmpty
            await rebuildOffers()
        } catch {
            loadFailed = true
        }
    }

    private func rebuildOffers() async {
        var result: [ProOffer] = []
        if let yearly = products[Self.yearlyID] {
            var trial: String?
            if let intro = yearly.subscription?.introductoryOffer, intro.paymentMode == .freeTrial,
               await yearly.subscription?.isEligibleForIntroOffer == true {
                trial = Self.describe(period: intro.period) + " free"
            }
            result.append(ProOffer(id: yearly.id, kind: .yearly, title: "Yearly", price: yearly.displayPrice,
                                   period: "per year", trial: trial, badge: "Best value"))
        }
        if let monthly = products[Self.monthlyID] {
            result.append(ProOffer(id: monthly.id, kind: .monthly, title: "Monthly", price: monthly.displayPrice,
                                   period: "per month", trial: nil, badge: nil))
        }
        if let lifetime = products[Self.lifetimeID] {
            result.append(ProOffer(id: lifetime.id, kind: .lifetime, title: "Lifetime", price: lifetime.displayPrice,
                                   period: "one time", trial: nil, badge: nil))
        }
        offers = result
    }

    private static func describe(period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day: return n == 7 ? "7 days" : "\(n) days"
        case .week: return n == 1 ? "7 days" : "\(n * 7) days"
        case .month: return n == 1 ? "1 month" : "\(n) months"
        case .year: return n == 1 ? "1 year" : "\(n) years"
        @unknown default: return "\(n)"
        }
    }

    /// Reads current purchases from the App Store. A refunded or expired purchase drops out here.
    public func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.allIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            owned = true
        }
        isPro = owned
    }

    public func purchase(_ offer: ProOffer) async {
        guard let product = products[offer.id], !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    message = "The purchase could not be verified."
                }
            case .pending:
                message = "The purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase failed: \(error.localizedDescription)"
        }
    }

    /// "Restore Purchases": asks the App Store to sync, then re-reads what the user owns.
    public func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isUnlocked ? "Sightline Pro restored." : "No earlier purchase was found for this Apple Account."
        } catch {
            message = "Restoring failed: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// Sample plans for screenshots and previews, in debug builds only.
    public func useSampleOffers() {
        offers = [
            ProOffer(id: Self.yearlyID, kind: .yearly, title: "Yearly", price: "$29.99", period: "per year", trial: "7 days free", badge: "Best value"),
            ProOffer(id: Self.monthlyID, kind: .monthly, title: "Monthly", price: "$4.99", period: "per month", trial: nil, badge: nil),
            ProOffer(id: Self.lifetimeID, kind: .lifetime, title: "Lifetime", price: "$59.99", period: "one time", trial: nil, badge: nil),
        ]
        loadFailed = false
    }
    #endif
}
