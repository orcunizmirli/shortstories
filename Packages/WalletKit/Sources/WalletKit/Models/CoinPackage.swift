/// CoinMagazasi paket kataloğu kalemi (05 §4.5 `GET /wallet/packages`). Coin adetleri, bonus
/// kademeleri ve rozet metinleri SUNUCUDAN gelir — istemcide hardcoded coin/bonus yoktur
/// (06 §2.2). USD fiyat burada değil, StoreKit `Product.displayPrice`'tedir (06 §11.2).
public struct CoinPackage: Sendable, Equatable, Identifiable, Decodable {
    public var id: String {
        productId
    }

    public let productId: String
    public let baseCoins: Int
    public let bonusPercent: Int
    public let bonusCoins: Int
    /// İlk yükleme 2x teklifinde uygulanacak bonus (06 §2.3); `firstTopUpEligible` iken gösterilir.
    public let firstTopUpBonusCoins: Int
    /// Sunucudan lokalize ("EN POPÜLER"/"EN İYİ DEĞER"); `nil` ise rozet çizilmez.
    public let badge: String?

    public init(
        productId: String,
        baseCoins: Int,
        bonusPercent: Int,
        bonusCoins: Int,
        firstTopUpBonusCoins: Int,
        badge: String?
    ) {
        self.productId = productId
        self.baseCoins = baseCoins
        self.bonusPercent = bonusPercent
        self.bonusCoins = bonusCoins
        self.firstTopUpBonusCoins = firstTopUpBonusCoins
        self.badge = badge
    }

    /// Standart toplam (baz + bonus).
    public var totalCoins: Int {
        baseCoins + bonusCoins
    }

    /// İlk yükleme 2x uygulanınca gösterilecek toplam (06 §2.3, 05 §4.5): baz + firstTopUp bonusu.
    public var firstTopUpTotalCoins: Int {
        baseCoins + firstTopUpBonusCoins
    }
}

/// `GET /wallet/packages` yanıtı (05 §4.5). `packages` dizisinin sırası UI sırasıdır.
public struct CoinPackageCatalog: Sendable, Equatable, Decodable {
    public let packages: [CoinPackage]
    public let firstTopUpEligible: Bool
    public let ttlSec: Int

    public init(packages: [CoinPackage], firstTopUpEligible: Bool, ttlSec: Int) {
        self.packages = packages
        self.firstTopUpEligible = firstTopUpEligible
        self.ttlSec = ttlSec
    }
}
