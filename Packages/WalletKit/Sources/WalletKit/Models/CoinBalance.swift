/// İki alt keseli coin bakiyesi (kanon §5; 05 §2.5). `purchased` = IAP ile alınmış (süresiz,
/// App Store komisyon matrahı); `earned` = check-in/görev/rewarded ad (süreli olabilir).
/// Kullanıcıya toplam gösterilir; ayrım muhasebe + harcama önceliği içindir.
public struct CoinBalance: Sendable, Equatable {
    public let purchasedCoins: Int
    public let earnedCoins: Int

    public init(purchasedCoins: Int, earnedCoins: Int) {
        self.purchasedCoins = purchasedCoins
        self.earnedCoins = earnedCoins
    }

    /// Kullanıcıya gösterilen tek sayı.
    public var totalCoins: Int {
        purchasedCoins + earnedCoins
    }

    /// İade sonrası eksi bakiye (05 §2.4): yeni unlock'lar bloklanır.
    public var isNegative: Bool {
        purchasedCoins < 0 || earnedCoins < 0
    }

    public static let zero = CoinBalance(purchasedCoins: 0, earnedCoins: 0)
}

/// Bir harcamanın kese-bazlı dökümü ve sonuç bakiyesi. Harcama önceliği **earned önce**
/// (kanon §5; 06 §2.4): önce kazanılmış coin, yetmezse purchased. Sunucu bu önceliği
/// otoritatif uygular; bu saf fonksiyon istemcinin **iyimser** (optimistic) ön-düşümü içindir.
public struct SpendPlan: Sendable, Equatable {
    public let earnedSpent: Int
    public let purchasedSpent: Int
    /// Düşüm sonrası bakiye (yalnız `isCovered` iken uygulanır).
    public let resulting: CoinBalance

    public var totalSpent: Int {
        earnedSpent + purchasedSpent
    }

    /// Bakiye harcamayı tam karşılıyor mu.
    public var isCovered: Bool {
        shortfall == 0
    }

    /// Eksik kalan coin (05 §4.5 `details.shortfall` istemci-tarafı türevi).
    public let shortfall: Int
}

/// Earned-önce harcama planlayıcısı — saf, yan etkisiz, izole test edilir.
public enum SpendPlanner {
    public static func plan(spending amount: Int, from balance: CoinBalance) -> SpendPlan {
        let request = max(0, amount)
        let earnedAvailable = max(0, balance.earnedCoins)
        let purchasedAvailable = max(0, balance.purchasedCoins)

        let earnedSpent = min(request, earnedAvailable)
        let remaining = request - earnedSpent
        let purchasedSpent = min(remaining, purchasedAvailable)
        let shortfall = remaining - purchasedSpent

        let resulting = CoinBalance(
            purchasedCoins: balance.purchasedCoins - purchasedSpent,
            earnedCoins: balance.earnedCoins - earnedSpent
        )
        return SpendPlan(
            earnedSpent: earnedSpent,
            purchasedSpent: purchasedSpent,
            resulting: resulting,
            shortfall: shortfall
        )
    }
}
