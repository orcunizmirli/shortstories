import Foundation

/// Kullanıcının hangi katmanda olduğu ve Free katman kotaları.
public enum SubscriptionTier: String, Sendable, Codable, Hashable {
    case free
    case pro
}

public struct Entitlement: Sendable, Codable, Hashable {
    public let tier: SubscriptionTier
    public let expiresAt: Date?
    /// Ödeme yeniden deneme / grace period — erişim sürer (06 §4).
    public let isInGracePeriod: Bool

    public init(tier: SubscriptionTier, expiresAt: Date? = nil, isInGracePeriod: Bool = false) {
        self.tier = tier
        self.expiresAt = expiresAt
        self.isInGracePeriod = isInGracePeriod
    }

    public static let free = Entitlement(tier: .free)

    public var isPro: Bool { tier == .pro }
}

/// Free katman sınırları (06 §3). Tek yerde tanımlıdır; UI ve pipeline aynı sabitleri okur.
public enum FreeTierLimits {
    /// En yeni kaç ekran görüntüsü indekslenir.
    public static let indexedShotCount = 200
    /// Ayda kaç doğal dil (LLM ayrıştırmalı) arama yapılabilir.
    public static let naturalLanguageSearchesPerMonth = 10
    /// Ayda kaç aksiyon (hatırlatıcı/takvim/kişi) oluşturulabilir.
    public static let actionsPerMonth = 3
    /// Kaç otomatik koleksiyon gösterilir.
    public static let visibleCollections = 3
}

/// Kota tüketen yetenekler.
public enum MeteredCapability: String, Sendable, Codable, CaseIterable, Hashable {
    case naturalLanguageSearch
    case action

    public var monthlyLimit: Int {
        switch self {
        case .naturalLanguageSearch: return FreeTierLimits.naturalLanguageSearchesPerMonth
        case .action: return FreeTierLimits.actionsPerMonth
        }
    }
}

/// Paywall'un hangi bağlamda açıldığı — metin seçimi ve frekans kapağı bunu kullanır (06 §5).
public enum PaywallTrigger: String, Sendable, Codable, Hashable {
    case indexLimitReached
    case searchQuotaExhausted
    case actionQuotaExhausted
    case proFeatureTapped
    case settings
}
