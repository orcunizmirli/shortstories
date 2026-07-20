import Foundation

/// Rewarded ad yüzeyinin (UnlockSheet satırı / OdulMerkezi kartı) SAF görünürlük kararı (SS-113,
/// 06 §9.2/§9.5). Yan etkisiz, izole test edilir. Girdiler tam olarak: ana şalter
/// (`rewardedAdsEnabled`, SS-024 remote flag) × doldurma (provider fill) × günlük cap için server'ın
/// verdiği KALAN HAK. VIP reklamsızlığı ve A/B kolu gibi ÜST kapılar `RewardedAdService`'te bu SAF
/// karardan ÖNCE uygulanır (VIP'e reklam SDK'sı hiç yoklanmaz).
///
/// SERVER-OTORİTER CAP (05 §963): istemci hakları ASLA kendi saymaz — `remaining` server'dan gelir
/// ("Bugün 3/5"). DOLDURMA YOKSA KART GİZLENİR (06 §9.5): envanter/yükleme yoksa yüzey render edilmez.
public enum RewardedAdAvailability: Sendable, Equatable {
    /// Reklam hazır ve hak var → yüzey görünür + etkin. `remaining` server'ın verdiği kalan hak
    /// ("N/5" göstergesi); server bildirmediyse `nil` (sayı gösterilmez ama satır etkin kalır).
    case available(remaining: Int?)
    /// Günlük cap doldu (server `remaining <= 0`) → yüzey GÖRÜNÜR ama DEVRE DIŞI ("Yarın yeni hakların
    /// olacak"). Tasarım gereği ödemeye dönüşüm baskısıdır (06 §9.2). `resetsAt` server'dan (05 §4.7).
    case capReached(resetsAt: Date?)
    /// Yüzey hiç render EDİLMEZ: ana şalter kapalı / doldurma yok (06 §9.5). VIP + A/B kolu kapalı
    /// durumları da servis katmanında bu sonuca çözülür.
    case hidden

    /// SAF karar (matris: flag × fill × cap). Öncelik sırası:
    /// 1. Ana şalter kapalı → gizli (server degrade kapısı).
    /// 2. Server "kalan hak" 0 → capReached (fill'den BAĞIMSIZ: cap sert bir sınırdır, görünür-devre dışı).
    /// 3. Doldurma yok → gizli (envanter/yükleme yok, 06 §9.5).
    /// 4. Aksi → available(kalan hak).
    public static func evaluate(
        rewardedAdsEnabled: Bool,
        hasFill: Bool,
        remaining: Int?,
        resetsAt: Date?
    ) -> RewardedAdAvailability {
        guard rewardedAdsEnabled else { return .hidden }
        if let remaining, remaining <= 0 {
            return .capReached(resetsAt: resetsAt)
        }
        guard hasFill else { return .hidden }
        return .available(remaining: remaining)
    }

    /// Yüzey render edilir mi (gizli DEĞİL). OdulMerkezi kartı / UnlockSheet satırı görünürlüğü.
    public var isVisible: Bool {
        if case .hidden = self {
            false
        } else {
            true
        }
    }

    /// Kullanıcı şu an reklam izleyebilir mi (yalnız `available`). capReached görünür ama devre dışıdır.
    public var isActionable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}

/// Rewarded ad A/B deney varyantı (SS-154, docs/08 E2). Deney ataması App katmanından ENJEKTE edilir;
/// RewardsKit deney kataloğunu (`AnalyticsKit.ExperimentCatalog`) import ETMEZ — yalnız çözülmüş
/// varyant değerini alır (R2 modül sınırı). `surfaceEnabled` görünürlük kararına (servis) ek kapıdır.
public enum RewardedAdVariant: String, Sendable, Equatable {
    /// Kontrol kolu: rewarded ad yüzeyi bu kolda KAPALI (docs/08 E2 control — coin birincil).
    case control
    /// Reklam satırı görünür ama ikincil (docs/08 E2 v2 — reklam seçeneği görünür, coin/VIP öne çıkar).
    case adSecondary

    /// Bu kolda rewarded ad yüzeyi gösterilir mi (availability ana şalterine ek A/B kapısı).
    public var surfaceEnabled: Bool {
        self != .control
    }

    /// Varsayılan kol: reklam satırı görünür-ikincil (deney atanmadıysa güvenli varsayılan).
    public static let `default` = RewardedAdVariant.adSecondary
}
