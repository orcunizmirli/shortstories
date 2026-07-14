import AppFoundation

/// UnlockSheet kilit-açma seçeneği türü (06 §6.2). Sabit sıralama: coin → reklam → VIP —
/// yalnız GÖRÜNÜR satırlar için (§6.2 görünürlük sözleşmesi).
public enum UnlockOptionKind: String, Sendable, Equatable, CaseIterable {
    case coin
    case ad
    case vip
}

/// Seçenek görünürlük sözleşmesi (06 §6.2): üç satır tek tek server bayrağıyla kapatılabilir
/// (`monetization.coin_enabled` / `ads.rewarded_enabled` / `monetization.vip_enabled`).
/// İstemcide satır listesi hardcoded değildir; bu değer `GET /config`'ten türetilir. Server en
/// az bir satırın açık kalmasını garanti eder (üçü birden kapatılamaz) — istemci bunu VARSAYAR.
public struct UnlockOptionsConfig: Equatable, Sendable {
    public let coinEnabled: Bool
    /// Faz 1'de reklam kapalıdır (06 §6.2); Faz 2'de `ads.rewarded_enabled` ile açılır.
    public let adEnabled: Bool
    public let vipEnabled: Bool

    public init(coinEnabled: Bool, adEnabled: Bool, vipEnabled: Bool) {
        self.coinEnabled = coinEnabled
        self.adEnabled = adEnabled
        self.vipEnabled = vipEnabled
    }

    /// Faz 1 varsayılanı: coin + VIP açık, reklam kapalı (06 §1.1/§6.2).
    public static let phase1 = UnlockOptionsConfig(coinEnabled: true, adEnabled: false, vipEnabled: true)
}

/// Coin ile aç satırının durumu (06 §6.2 birincil buton / §6.3 coin-yetersiz akışı).
public enum CoinUnlockState: Equatable, Sendable {
    /// Bakiye yeterli — birincil, vurgulu, dokununca kilidi açar.
    case sufficient(price: Int)
    /// Bakiye yetersiz — "N coin daha gerekli", dokununca CoinMagazasi (06 §6.3).
    case insufficient(price: Int, shortfall: Int)
    /// `unlockPrice` alınamadı (06 §6.6): buton devre dışı, reklam/VIP çalışır kalır.
    case priceUnavailable
    /// İade sonrası eksi bakiye (06 §6.6): tüm unlock'lar bloklu → CoinMagazasi yönlendirmesi.
    case balanceProblem
}

/// UnlockSheet'in saf, türetilmiş görünüm durumu — bakiye + fiyat + config + intro uygunluğu
/// girdilerinden hesaplanır (06 §6.2/§6.3). SwiftUI View bunu doğrudan çizer; @Observable model
/// bunu hesaplar ama mantık burada izole test edilir.
public struct UnlockSheetViewState: Equatable, Sendable {
    /// Görünür seçenekler, kanonik sırada (coin → ad → vip), yalnız bayrağı açık olanlar.
    public let orderedOptions: [UnlockOptionKind]
    /// Coin satırı durumu; coin bayrağı kapalıysa `nil` (satır hiç render edilmez).
    public let coinState: CoinUnlockState?
    /// VIP upsell satırında intro fiyat vurgusu gösterilsin mi (uygun + VIP bayrağı açık).
    public let showsVIPIntro: Bool
    /// Başlık bloğunda gösterilen güncel toplam bakiye.
    public let balanceTotal: Int

    public init(
        orderedOptions: [UnlockOptionKind],
        coinState: CoinUnlockState?,
        showsVIPIntro: Bool,
        balanceTotal: Int
    ) {
        self.orderedOptions = orderedOptions
        self.coinState = coinState
        self.showsVIPIntro = showsVIPIntro
        self.balanceTotal = balanceTotal
    }

    /// Analitik `options_shown` parametresi (06 §6.7 / 08 §3.4): "coin,ad,vip" alt kümesi.
    public var optionsShownParameter: String {
        orderedOptions.map(\.rawValue).joined(separator: ",")
    }

    /// Saf türetim. `unlockPrice == nil` → fiyat yüklenemedi; eksi bakiye → balanceProblem
    /// (fiyattan ÖNCE, iade sonrası tüm unlock'lar bloklu, 06 §6.6).
    public static func resolve(
        balance: CoinBalance,
        unlockPrice: Int?,
        config: UnlockOptionsConfig,
        vipIntroEligible: Bool
    ) -> UnlockSheetViewState {
        var order: [UnlockOptionKind] = []
        var coinState: CoinUnlockState?
        if config.coinEnabled {
            order.append(.coin)
            coinState = resolveCoinState(balance: balance, unlockPrice: unlockPrice)
        }
        if config.adEnabled {
            order.append(.ad)
        }
        if config.vipEnabled {
            order.append(.vip)
        }
        return UnlockSheetViewState(
            orderedOptions: order,
            coinState: coinState,
            showsVIPIntro: config.vipEnabled && vipIntroEligible,
            balanceTotal: balance.totalCoins
        )
    }

    private static func resolveCoinState(balance: CoinBalance, unlockPrice: Int?) -> CoinUnlockState {
        if balance.isNegative {
            return .balanceProblem
        }
        guard let price = unlockPrice else {
            return .priceUnavailable
        }
        if balance.totalCoins >= price {
            return .sufficient(price: price)
        }
        return .insufficient(price: price, shortfall: price - balance.totalCoins)
    }
}
