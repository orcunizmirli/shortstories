import AppFoundation
import Foundation

/// Entitlement değişikliği yayını yükü (SS-097). `WalletStore` VIP durumu değiştiğinde
/// (başladı/bitti/grace) ya da bir bölüm açıldığında bunu yayınlar; PlayerKit'in kilit
/// kontrolü `EntitlementChecking.hasAccess` ile pull-based okur, bu akış ise push-based
/// tazeleme (≤5 sn hedefi) içindir. Combine YOK — AsyncStream (kanon §2).
public struct EntitlementSnapshot: Sendable, Equatable {
    public let isVIP: Bool
    public let vipExpiresAt: Date?
    public let isInGracePeriod: Bool
    /// Bu yayına sebep olan yeni açılan bölüm (varsa) — o an izlenen kilitli bölümün
    /// UI'ının anında güncellenmesi için.
    public let lastUnlockedEpisode: EpisodeID?

    public init(
        isVIP: Bool,
        vipExpiresAt: Date?,
        isInGracePeriod: Bool,
        lastUnlockedEpisode: EpisodeID?
    ) {
        self.isVIP = isVIP
        self.vipExpiresAt = vipExpiresAt
        self.isInGracePeriod = isInGracePeriod
        self.lastUnlockedEpisode = lastUnlockedEpisode
    }
}
