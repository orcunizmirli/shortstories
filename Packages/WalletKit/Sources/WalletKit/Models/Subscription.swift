import Foundation

/// VIP abonelik durumu (05 §2.8). Doğruluk kaynağı SUNUCUDUR (App Store Server Notifications
/// V2 ile güncellenir, 06 §5.1); istemci StoreKit `Transaction.currentEntitlements`'ı yalnız
/// hızlı yerel ipucu olarak kullanır (06 §4.5). Grace period boyunca `isVIP` korunur.
public struct SubscriptionStatus: Sendable, Equatable, Decodable {
    public let isVIP: Bool
    public let plan: Plan?
    public let expiresAt: Date?
    public let willAutoRenew: Bool
    /// Billing retry / grace: `true` iken erişim kesilmez (06 §8.4).
    public let isInGracePeriod: Bool
    public let isInIntroOffer: Bool
    public let dailyBonusCoins: Int
    public let dailyBonusClaimedToday: Bool
    /// Sunucunun bu snapshot'ı ürettiği an (05 §2.8). Out-of-order koruması için monoton recency
    /// sinyalidir: `WalletStore.applySubscription` daha ESKİ `updatedAt`'lı snapshot'ı uygulamaz
    /// (taze VIP'i bayat non-VIP ezmesin). Opsiyonel — sunucu göndermezse (`nil`) guard atlanır ve
    /// son-yazan-kazanır'a düşülür (geriye uyum). `Decodable`: alan yoksa `nil` (decodeIfPresent).
    public let updatedAt: Date?

    public init(
        isVIP: Bool,
        plan: Plan?,
        expiresAt: Date?,
        willAutoRenew: Bool,
        isInGracePeriod: Bool,
        isInIntroOffer: Bool,
        dailyBonusCoins: Int,
        dailyBonusClaimedToday: Bool,
        updatedAt: Date? = nil
    ) {
        self.isVIP = isVIP
        self.plan = plan
        self.expiresAt = expiresAt
        self.willAutoRenew = willAutoRenew
        self.isInGracePeriod = isInGracePeriod
        self.isInIntroOffer = isInIntroOffer
        self.dailyBonusCoins = dailyBonusCoins
        self.dailyBonusClaimedToday = dailyBonusClaimedToday
        self.updatedAt = updatedAt
    }

    public enum Plan: String, Sendable, Equatable, CaseIterable, Decodable, UnknownDecodable {
        case weekly
        case monthly
        case yearly
        case unknown
    }

    /// VIP tüm bölümlere erişim verir (kanon §5). Grace period sunucuda `isVIP=true` ile
    /// korunduğundan tek bayrak yeterlidir.
    public var grantsFullAccess: Bool {
        isVIP
    }

    /// Abonelik yokken temel durum.
    public static let none = SubscriptionStatus(
        isVIP: false,
        plan: nil,
        expiresAt: nil,
        willAutoRenew: false,
        isInGracePeriod: false,
        isInIntroOffer: false,
        dailyBonusCoins: 0,
        dailyBonusClaimedToday: false
    )

    /// StoreKit `currentEntitlements`'tan türetilen iyimser VIP (sunucu erişilene kadar);
    /// plan/expiry bilinmez, sunucu snapshot'ı gelince ezilir (06 §4.5).
    public static let optimisticVIP = SubscriptionStatus(
        isVIP: true,
        plan: nil,
        expiresAt: nil,
        willAutoRenew: true,
        isInGracePeriod: false,
        isInIntroOffer: false,
        dailyBonusCoins: 0,
        dailyBonusClaimedToday: false
    )
}

/// Satın alınabilir VIP planı (06 §3.1/§3.2). Üç plan tek subscription group'ta; yalnız
/// süre/fiyatta ayrışır. Product ID şeması `com.shortseries.vip.<dönem>`.
public enum SubscriptionPlan: String, Sendable, Equatable, CaseIterable {
    case weekly
    case monthly
    case yearly

    public var productID: String {
        "com.shortseries.vip.\(rawValue)"
    }

    public init?(productID: String) {
        guard let plan = SubscriptionPlan.allCases.first(where: { $0.productID == productID }) else {
            return nil
        }
        self = plan
    }
}
