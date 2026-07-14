/// CoinMagazasi'nda gösterilecek birleşik paket kalemi: backend kataloğu (coin/bonus/rozet,
/// `GET /wallet/packages`) + StoreKit ürünü (yerelleştirilmiş fiyat). İki kaynak `productId`
/// üzerinden eşlenir (05 §4.5, 06 §4.2). Saf değer tipi — UI dilimi bunu tüketir.
public struct CoinShopItem: Sendable, Equatable, Identifiable {
    public var id: String {
        productId
    }

    public let productId: String
    public let package: CoinPackage
    public let displayPrice: String
    /// İlk yükleme 2x teklifi bu kalem için gösterilecek mi (server kararı).
    public let firstTopUpEligible: Bool

    public init(productId: String, package: CoinPackage, displayPrice: String, firstTopUpEligible: Bool) {
        self.productId = productId
        self.package = package
        self.displayPrice = displayPrice
        self.firstTopUpEligible = firstTopUpEligible
    }

    /// Kartta gösterilecek toplam coin: ilk yükleme uygunsa 2x toplam, değilse standart.
    public var displayedTotalCoins: Int {
        firstTopUpEligible ? package.firstTopUpTotalCoins : package.totalCoins
    }
}

/// VIPAbonelik'te gösterilecek birleşik plan: satın alınabilir plan + StoreKit ürünü
/// (fiyat + intro offer). Intro yalnız `isEligibleForIntroOffer` iken gösterilir (06 §8.2).
public struct VIPPlanOption: Sendable, Equatable, Identifiable {
    public var id: String {
        product.id
    }

    public let plan: SubscriptionPlan
    public let product: StoreProduct

    public init(plan: SubscriptionPlan, product: StoreProduct) {
        self.plan = plan
        self.product = product
    }

    /// Intro offer UI'da gösterilmeli mi (uygun + offer var).
    public var showsIntroOffer: Bool {
        guard let subscription = product.subscription else { return false }
        return subscription.isEligibleForIntroOffer && subscription.introOffer != nil
    }

    /// Gösterilecek intro offer (yalnız `showsIntroOffer` iken).
    public var effectiveIntroOffer: IntroOffer? {
        showsIntroOffer ? product.subscription?.introOffer : nil
    }
}

/// Backend paket kataloğunu StoreKit ürünleriyle birleştiren saf join (06 §4.2). StoreKit'te
/// karşılığı olmayan paket ATLANIR (ASC'de pasif ürün → kart gizlenir). Sıra: katalog sırası.
public enum StorefrontMerge {
    public static func coinShop(
        catalog: CoinPackageCatalog,
        products: [StoreProduct]
    ) -> [CoinShopItem] {
        let priceByID = Dictionary(
            products.map { ($0.id, $0.displayPrice) },
            uniquingKeysWith: { first, _ in first }
        )
        return catalog.packages.compactMap { package in
            guard let displayPrice = priceByID[package.productId] else { return nil }
            return CoinShopItem(
                productId: package.productId,
                package: package,
                displayPrice: displayPrice,
                firstTopUpEligible: catalog.firstTopUpEligible
            )
        }
    }

    public static func vipPlans(products: [StoreProduct]) -> [VIPPlanOption] {
        products.compactMap { product in
            guard let plan = SubscriptionPlan(productID: product.id) else { return nil }
            return VIPPlanOption(plan: plan, product: product)
        }
    }
}
