import Foundation

/// Eski/lapsed VIP'e sunulan indirimli dönüş offer'ının taşıma-bağımsız değer temsili
/// (SS-099 F2; 07 §7 "Eski VIP" → indirimli dönüş fiyatı, StoreKit 2 win-back offer / offer
/// code). `IntroOffer` ile aynı desen: fiyat/süre StoreKit'ten okunur, istemcide HARDCODE
/// edilmez (06 §11.2). Uygunluğu StoreKit belirler; uygun olmayana offer GÖSTERİLMEZ (06 §8.2).
public struct WinBackOffer: Sendable, Equatable {
    /// Yerelleştirilmiş, storefront para birimindeki indirimli dönüş fiyatı (USD hardcode YASAK).
    public let displayPrice: String
    public let paymentMode: PaymentMode
    public let periodUnit: PeriodUnit
    public let periodValue: Int
    public let periodCount: Int

    public init(
        displayPrice: String,
        paymentMode: PaymentMode,
        periodUnit: PeriodUnit,
        periodValue: Int,
        periodCount: Int
    ) {
        self.displayPrice = displayPrice
        self.paymentMode = paymentMode
        self.periodUnit = periodUnit
        self.periodValue = periodValue
        self.periodCount = periodCount
    }

    /// SAF türetim: üründen win-back offer GRACEFUL okunur — offer yoksa (abonelik ürünü değil,
    /// StoreKit uygunluk vermemiş ya da canlı katman henüz doldurmamış) `nil` döner (06 §8.2
    /// "uygun olmayana gösterme"; intro deseni). Fiyat üründeki `displayPrice`'tandır, hesaplanmaz.
    public static func resolve(from product: StoreProduct) -> WinBackOffer? {
        product.subscription?.winBackOffer
    }
}
