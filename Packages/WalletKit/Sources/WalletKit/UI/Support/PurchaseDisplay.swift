import Foundation

/// CoinMagazasi kart gösterim türevleri (06 §7.2/§7.3). SAF hesaplar — coin/bonus adetleri
/// çekirdek `CoinPackage`'tan gelir (istemcide hardcoded coin YOK, 06 §2.2); bu extension
/// yalnız SUNUM biçimini türetir. İzole test edilir.
public extension CoinShopItem {
    /// Bonus rozeti metni (06 §7.2): Tier1 (%0) rozetsizdir → `nil`.
    var bonusBadgeText: String? {
        package.bonusPercent > 0 ? "+%\(package.bonusPercent) BONUS" : nil
    }

    /// Katalog rozeti ("EN POPÜLER"/"EN İYİ DEĞER") — sunucudan gelir, deneyle değişir; yoksa `nil`.
    var catalogBadge: String? {
        package.badge
    }

    /// Bonus dahil standart toplam (ilk-yükleme uygunken üstü çizili gösterilecek referans, 06 §7.3).
    var standardTotalCoins: Int {
        package.totalCoins
    }

    /// İlk-yükleme 2x aktif mi — büyük `displayedTotalCoins` + üstü çizili `standardTotalCoins`
    /// (06 §7.3). Üstü çizilen COIN adedidir, fiyat değil (06 §11.2 yanıltıcı fiyat yasağı).
    var showsFirstTopUpDoubling: Bool {
        firstTopUpEligible && package.firstTopUpTotalCoins > package.totalCoins
    }
}

/// VIPAbonelik plan kartı gösterim türevleri (06 §8.1). Fiyat StoreKit `displayPrice`'tan;
/// USD hardcode YASAK (06 §11.2). İntro yalnız `showsIntroOffer` iken (06 §8.2).
public extension VIPPlanOption {
    /// Gösterilecek normal (dönem başı) fiyat — yerelleştirilmiş.
    var displayPrice: String {
        product.displayPrice
    }

    /// Plan dönem birimi (kart etiketi View'da lokalize edilir).
    var periodUnit: PeriodUnit {
        product.subscription?.periodUnit ?? plan.defaultPeriodUnit
    }

    /// "En avantajlı" rozeti yıllık planda (06 §8.1). Deney varsayılan seçimi de yıllıktır (§10 M?).
    var isBestValue: Bool {
        plan == .yearly
    }
}

/// VIP plan fiyat/intro kopyası — SAF, izole test edilir (06 §8.1/§11.2). Çok-dönemli intro'da
/// süre `periodValue × periodCount` toplamıyla gösterilir (yalnız `periodUnit` DEĞİL); aksi halde
/// "ilk 3 ay $9.99" gibi bir teklif "ilk ay $9.99" olarak yanlış/yanıltıcı fiyat basında görünürdü
/// (06 §11.2). Süre StoreKit'ten okunur; USD hardcode yok (fiyat `displayPrice`'tan).
public enum VIPPlanCopy {
    /// Dönem birimi tekil adı (Türkçe): gün/hafta/ay/yıl.
    public static func periodNoun(_ unit: PeriodUnit) -> String {
        switch unit {
        case .day: "gün"
        case .week: "hafta"
        case .month: "ay"
        case .year: "yıl"
        }
    }

    /// Intro teklifinin toplam süre ifadesi: tek birim → "hafta"; çok dönem → "3 ay"
    /// (`periodValue × periodCount`). payUpFront (value=3/count=1) ve payAsYouGo (value=1/count=3)
    /// kodlamalarının ikisi de aynı toplam süreyi verir.
    public static func introDuration(_ intro: IntroOffer) -> String {
        let units = max(1, intro.periodValue) * max(1, intro.periodCount)
        let noun = periodNoun(intro.periodUnit)
        return units == 1 ? noun : "\(units) \(noun)"
    }

    /// Plan fiyat alt satırı: intro yoksa "X/hafta"; intro varsa "İlk 3 ay X, sonra Y/hafta".
    public static func priceSubtitle(for option: VIPPlanOption) -> String {
        let regular = "\(option.displayPrice)/\(periodNoun(option.periodUnit))"
        guard let intro = option.effectiveIntroOffer else { return regular }
        return "İlk \(introDuration(intro)) \(intro.displayPrice), sonra \(regular)"
    }

    /// CTA intro son eki: intro varsa "ilk 3 ay X"; yoksa `nil` (CTA "VIP Ol" gösterir).
    public static func introCTASuffix(for option: VIPPlanOption?) -> String? {
        guard let option, let intro = option.effectiveIntroOffer else { return nil }
        return "ilk \(introDuration(intro)) \(intro.displayPrice)"
    }
}

public extension SubscriptionPlan {
    /// StoreKit ürünü dönem bilgisi taşımadığında kullanılacak kanonik dönem (06 §3.2).
    var defaultPeriodUnit: PeriodUnit {
        switch self {
        case .weekly: .week
        case .monthly: .month
        case .yearly: .year
        }
    }

    /// Kanonik satın alma/görünüm sırası: haftalık < aylık < yıllık (06 §3.3 subscription group).
    var displayOrder: Int {
        switch self {
        case .weekly: 0
        case .monthly: 1
        case .yearly: 2
        }
    }

    /// Analitik `product_id` kısaltması (08 §3.4: `vip_weekly`/`vip_monthly`/`vip_yearly`).
    var analyticsID: String {
        "vip_\(rawValue)"
    }
}
