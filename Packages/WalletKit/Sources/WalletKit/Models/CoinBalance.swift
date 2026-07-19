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

/// Bir sonraki harcamanın tek kese satırı (06 §2.4). Sunucu ledger'ının kese-başına satır
/// düzeniyle (05 §2.6: "iki satır") aynı anlamı UI'ya taşır; `bucket` yalnız `.earned`/
/// `.purchased` olur (harcama ön-izlemesinde `.unknown` üretilmez).
public struct SpendSource: Sendable, Equatable {
    public let bucket: CoinTransaction.Bucket
    public let coins: Int

    public init(bucket: CoinTransaction.Bucket, coins: Int) {
        self.bucket = bucket
        self.coins = coins
    }
}

/// Earned-önce harcama kuralının (E9; 06 §2.4) UI'ya açılan ŞEFFAF okumaları. Saf türev;
/// bakiye/düşüm otoritesi sunucudadır. UnlockSheet "önce kazanılmış coin'den düşülür" bandı
/// bunları kullanır.
public extension SpendPlan {
    /// Harcamanın kese-bazlı dökümü, harcama SIRASINDA (önce earned, sonra purchased). Yalnız
    /// fiilen düşen (> 0) satırlar; karışık düşüşte iki satır (ledger'la birebir).
    var sources: [SpendSource] {
        var lines: [SpendSource] = []
        if earnedSpent > 0 {
            lines.append(SpendSource(bucket: .earned, coins: earnedSpent))
        }
        if purchasedSpent > 0 {
            lines.append(SpendSource(bucket: .purchased, coins: purchasedSpent))
        }
        return lines
    }

    /// Bir sonraki harcamanın İLK çektiği kese (banner metni için). Hiç düşüm yoksa `nil`.
    var primaryBucket: CoinTransaction.Bucket? {
        sources.first?.bucket
    }

    /// Harcama iki keseden karışık mı düşüyor (ledger iki satır → UI "X kazanılmış + Y satın
    /// alınmış" açıklaması).
    var drawsFromBothBuckets: Bool {
        earnedSpent > 0 && purchasedSpent > 0
    }

    /// UnlockSheet earned-önce şeffaflık satırının (SS-115 D2) içeriği. Yalnız harcama TAM karşılanır
    /// (`isCovered`) VE earned keseden pay düşerken doludur; yalnız-purchased veya karşılanamayan
    /// (shortfall) durumda `nil` (satır çizilmez — "önce earned" anlatılacak bir şey yok).
    var earnedFirstNote: EarnedFirstNote? {
        guard isCovered, earnedSpent > 0 else { return nil }
        if purchasedSpent > 0 {
            return .mixed(earned: earnedSpent, purchased: purchasedSpent)
        }
        return .earnedOnly(coins: earnedSpent)
    }
}

/// Earned-önce harcama kuralının (kanon §5; 06 §2.4) UnlockSheet'e açılan ŞEFFAF okuması
/// (SS-115 D2). Saf türev; mesaj TEK kaynak burada (View verbatim çizer, test doğrular).
public enum EarnedFirstNote: Sendable, Equatable {
    /// Unlock tamamen kazanılmış coin'den düşer.
    case earnedOnly(coins: Int)
    /// Karışık düşüş: önce earned, sonra purchased (ledger iki satır, 05 §2.6).
    case mixed(earned: Int, purchased: Int)

    /// Coin butonunun altına basılan açıklama. "Önce kazanılmış" ifadesiyle earned-önce kuralını
    /// (E9) kullanıcıya görünür kılar (sürpriz vade kaybı → kayıp kaçınma, 06 §2.5).
    public var message: String {
        switch self {
        case let .earnedOnly(coins):
            "Önce kazanılmış \(coins) coin'in kullanılır"
        case let .mixed(earned, purchased):
            "Önce kazanılmış \(earned) coin, sonra satın alınan \(purchased) coin kullanılır"
        }
    }
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
