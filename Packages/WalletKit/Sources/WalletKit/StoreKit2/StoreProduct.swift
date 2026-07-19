import Foundation

/// StoreKit `Product`'ın taşıma-bağımsız değer temsili. StoreKit tipleri yalnız `StoreKit2/`
/// canlı katmanında görünür (R6); portlar ve WalletStore bu değer tipiyle konuşur, böylece
/// testler StoreKit config dosyası olmadan fake port ile koşar.
public struct StoreProduct: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// Yerelleştirilmiş, storefront para biriminde fiyat (06 §11.2 — USD hardcode YASAK).
    public let displayPrice: String
    public let price: Decimal
    public let kind: ProductKind
    /// Yalnız `.subscription` için dolu.
    public let subscription: SubscriptionInfo?

    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        price: Decimal,
        kind: ProductKind,
        subscription: SubscriptionInfo?
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
        self.kind = kind
        self.subscription = subscription
    }

    public enum ProductKind: String, Sendable, Equatable {
        case coinPack
        case subscription
        case other
    }
}

/// Abonelik ürününün dönem + intro/win-back offer bilgisi (06 §4.8 / §5.1 / §8.2).
public struct SubscriptionInfo: Sendable, Equatable {
    /// StoreKit belirler; uygun olmayan kullanıcıya intro fiyatı GÖSTERİLMEZ (06 §3.3).
    public let isEligibleForIntroOffer: Bool
    /// Yalnız uygun kullanıcı için dolu (intro fiyat/süre StoreKit'ten okunur, hardcode değil).
    public let introOffer: IntroOffer?
    public let periodUnit: PeriodUnit
    public let periodValue: Int
    /// Eski/lapsed VIP'e sunulan indirimli dönüş offer'ı (SS-099 win-back; StoreKit 2 win-back
    /// offer, iOS 18+). Uygunluğu StoreKit belirler → uygun olmayana `nil` gösterilmez (06 §8.2
    /// intro deseni). Fiyat `displayPrice`'tan; USD hardcode YASAK (06 §11.2). Canlı katman
    /// doldurana dek `nil` (graceful) — `WinBackOffer.resolve` bunu yansıtır.
    public let winBackOffer: WinBackOffer?

    public init(
        isEligibleForIntroOffer: Bool,
        introOffer: IntroOffer?,
        periodUnit: PeriodUnit,
        periodValue: Int,
        winBackOffer: WinBackOffer? = nil
    ) {
        self.isEligibleForIntroOffer = isEligibleForIntroOffer
        self.introOffer = introOffer
        self.periodUnit = periodUnit
        self.periodValue = periodValue
        self.winBackOffer = winBackOffer
    }
}

/// Introductory offer (VIP haftalık ilk hafta $3.99 — 06 §4.8). Metin StoreKit verisinden.
public struct IntroOffer: Sendable, Equatable {
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
}

public enum PeriodUnit: String, Sendable, Equatable {
    case day
    case week
    case month
    case year
}

public enum PaymentMode: String, Sendable, Equatable {
    case payUpFront
    case payAsYouGo
    case freeTrial
}
