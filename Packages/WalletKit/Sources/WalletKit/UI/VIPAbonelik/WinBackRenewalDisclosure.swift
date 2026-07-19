import Foundation

/// Fiyatlı win-back CTA'sına BİTİŞİK gösterilecek App Store §11.4 açıklamasının bileşenleri
/// (SS-099 F1 — Guideline 3.1.2; docs 06 §11.4/§8.5). Otomatik-yenileme cümlesinin yanında
/// offer fiyatı + dönemi + offer-sonrası NORMAL fiyat/dönem birlikte sunulur (offer haftalık ama
/// plan yıllıkken dönem yanıltmasını da giderir). Fiyat/dönem StoreKit'ten okunur; USD/dönem
/// HARDCODE YASAK (06 §11.2). SAF değer tipi — View `priceSummary`'yi verbatim çizer, test doğrular.
public struct WinBackRenewalDisclosure: Sendable, Equatable {
    /// İndirimli dönüş (offer) fiyatı — yerelleştirilmiş.
    public let offerPrice: String
    /// Offer'ın toplam süresi (ör. "hafta" / "3 ay").
    public let offerPeriod: String
    /// Offer-sonrası normal (yenileme) fiyatı — yerelleştirilmiş.
    public let regularPrice: String
    /// Normal yenileme dönemi (ör. "yıl").
    public let regularPeriod: String

    public init(offerPrice: String, offerPeriod: String, regularPrice: String, regularPeriod: String) {
        self.offerPrice = offerPrice
        self.offerPeriod = offerPeriod
        self.regularPrice = regularPrice
        self.regularPeriod = regularPeriod
    }

    /// §11.4 fiyat/dönem özeti (View verbatim çizer; altına statik otomatik-yenileme cümleleri gelir).
    public var priceSummary: String {
        "İlk \(offerPeriod) \(offerPrice), sonra \(regularPrice)/\(regularPeriod)"
    }

    /// GRACEFUL türetim: offer + normal fiyat/dönem TAM ise dolu; herhangi bir parça eksikse (canlı
    /// katman fiyatı henüz doldurmadıysa) `nil` → fiyatlı CTA gösterilmez (compliance > gösterim).
    public static func resolve(from option: VIPPlanOption?) -> WinBackRenewalDisclosure? {
        guard let option,
              let subscription = option.product.subscription,
              let offer = subscription.winBackOffer,
              !offer.displayPrice.isEmpty,
              !option.product.displayPrice.isEmpty else { return nil }
        return WinBackRenewalDisclosure(
            offerPrice: offer.displayPrice,
            offerPeriod: VIPPlanCopy.periodDuration(
                unit: offer.periodUnit,
                value: offer.periodValue,
                count: offer.periodCount
            ),
            regularPrice: option.product.displayPrice,
            regularPeriod: VIPPlanCopy.periodNoun(subscription.periodUnit)
        )
    }
}
