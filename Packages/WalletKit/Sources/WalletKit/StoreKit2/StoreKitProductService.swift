import AppFoundation
import StoreKit

/// Canlı StoreKit ürün servisi (SS-090): `Product.products(for:)` ile yükler, ham `Product`'ları
/// satın alma için cache'ler ve taşıma-bağımsız `StoreProduct`'a map eder. StoreKit tipleri bu
/// dosyada hapsolur (R6). `actor` — ürün cache'i paylaşılan değişken durumdur.
public actor StoreKitProductService: ProductProviding {
    private var cache: [String: Product] = [:]
    private let analytics: any AnalyticsTracking

    public init(analytics: any AnalyticsTracking) {
        self.analytics = analytics
    }

    public func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        let products = try await Product.products(for: ids)
        var mapped: [StoreProduct] = []
        for product in products {
            cache[product.id] = product
            await mapped.append(StoreProduct(product))
        }
        reportMissingProducts(requested: ids, loadedIDs: mapped.map(\.id))
        return mapped
    }

    /// ASC'de pasif/reddedilmiş ürün → App Store istenen ID'yi eksik döndürebilir (06 §4.2).
    /// Her eksik ID için `iap_product_missing` emit edilir (UI o ID'yi gizler + loglar). Saf,
    /// StoreKit'siz izole edilebilir seam (birim testi bunu doğrudan çağırır).
    func reportMissingProducts(requested: [String], loadedIDs: [String]) {
        let loaded = Set(loadedIDs)
        for id in requested where !loaded.contains(id) {
            analytics.track("iap_product_missing", parameters: ["product_id": .string(id)])
        }
    }

    /// PurchaseService'in satın almadan önce ham `Product`'a erişmesi için (aynı aktör-dışı
    /// resolve; canlı kompozisyonda tek `StoreKitProductService` paylaşılır).
    func rawProduct(id: String) -> Product? {
        cache[id]
    }

    func cache(_ products: [Product]) {
        for product in products {
            cache[product.id] = product
        }
    }
}

extension StoreProduct {
    /// StoreKit `Product` → taşıma-bağımsız değer. Intro uygunluğu async okunur (06 §4.8).
    init(_ product: Product) async {
        let kind: ProductKind = switch product.type {
        case .consumable:
            .coinPack
        case .autoRenewable:
            .subscription
        default:
            .other
        }

        var subscriptionInfo: SubscriptionInfo?
        if let subscription = product.subscription {
            let eligible = await subscription.isEligibleForIntroOffer
            let intro = subscription.introductoryOffer.map { IntroOffer($0) }
            subscriptionInfo = SubscriptionInfo(
                isEligibleForIntroOffer: eligible,
                introOffer: eligible ? intro : nil,
                periodUnit: PeriodUnit(subscription.subscriptionPeriod.unit),
                periodValue: subscription.subscriptionPeriod.value
            )
        }

        self.init(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            price: product.price,
            kind: kind,
            subscription: subscriptionInfo
        )
    }
}

extension IntroOffer {
    init(_ offer: Product.SubscriptionOffer) {
        let mode: PaymentMode = switch offer.paymentMode {
        case .payUpFront:
            .payUpFront
        case .payAsYouGo:
            .payAsYouGo
        case .freeTrial:
            .freeTrial
        default:
            .payUpFront
        }
        self.init(
            displayPrice: offer.displayPrice,
            paymentMode: mode,
            periodUnit: PeriodUnit(offer.period.unit),
            periodValue: offer.period.value,
            periodCount: offer.periodCount
        )
    }
}

extension PeriodUnit {
    init(_ unit: Product.SubscriptionPeriod.Unit) {
        switch unit {
        case .day:
            self = .day
        case .week:
            self = .week
        case .month:
            self = .month
        case .year:
            self = .year
        @unknown default:
            self = .day
        }
    }
}
