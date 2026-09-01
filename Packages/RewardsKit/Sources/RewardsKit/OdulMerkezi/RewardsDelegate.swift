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

    /// Davet giriş kartından "Arkadaşını Davet Et" → App `DavetMerkeziView`'ı sunar (RWD-07). Kart
    /// `RewardsFlags.referralCard` ile gizlenir. Varsayılan boş → mevcut conformer'lar/testler kırılmaz.
    func rewardsOpensReferral()

    /// Check-in/görev claim'i SERVER-otoriter bakiyeyi kredilendirdi. Claim doğrudan API'ye gider,
    /// otoritatif `WalletStore`'a yansımaz → App koordinatörü bunu alıp `WalletStore.refresh()` tetiklemeli
    /// ki Profil/CoinShop gibi cüzdan-tabanlı ekranlar OdulMerkezi başlığıyla YAKINSASIN (oturum-içi ıraksama
    /// bulgusu #2). Varsayılan boş → mevcut conformer'lar/testler kırılmaz.
    func rewardsDidCreditBalance()
}

public extension RewardsDelegate {
    func rewardsDidClaimCheckIn(streakDay _: Int) {}
    func rewardsOpensReferral() {}
    func rewardsDidCreditBalance() {}
}
