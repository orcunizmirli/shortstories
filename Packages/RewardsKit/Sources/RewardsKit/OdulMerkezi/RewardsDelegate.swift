/// `OdulMerkezi` navigasyon niyetleri — App koordinatörü bağlar (02 §4.9). WalletKit LibraryKit
/// PlayerKit vb. RewardsKit'e import EDİLMEZ; bağlam koordinatördedir (R2). Zayıf referans, MainActor.
///
/// F1 (SS-110/111) kapsamı: coin bakiyesi kartından CoinMagazasi kısayolu. Görev detayları (SS-112),
/// rewarded ad (SS-113), VIP tanıtım kartı ileride buraya eklenir.
@MainActor
public protocol RewardsDelegate: AnyObject {
    /// Bakiye kartı / "Coin Al" kısayolu → `CoinMagazasi` (02 §4.9 giriş noktası).
    func rewardsOpensCoinStore()

    /// Günlük check-in başarıyla claim edildi (streak günü) — POZİTİF an (RTG-01 App Store puanlama
    /// istemi; 00-genel-bakis.md §294). App koordinatörü bunu `ReviewPromptController`'a iletir.
    /// `streakDay`: kazanılan döngü günü (1–7). Varsayılan boş → mevcut conformer'lar/testler kırılmaz.
    func rewardsDidClaimCheckIn(streakDay: Int)
}

public extension RewardsDelegate {
    func rewardsDidClaimCheckIn(streakDay _: Int) {}
}
