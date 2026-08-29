import AppFoundation

/// RewardsKit-sahipli feature flag anahtarları (03 §11 tipli flag kalıbı). Varsayılan KODDADIR:
/// config gelmezse uygulama varsayılanla tam çalışır.
public enum RewardsFlags {
    /// Rewarded ad kartı görünürlüğü. F1'de KAPALI (yapı var, gizli); F2 SS-113 (AdMob köprüsü)
    /// açar. Kart yalnız flag açık VE doldurma varken gösterilir (SS-113 doldurma mantığı).
    public static let rewardedAdCard = FlagKey(name: "rewards.rewarded_ad_card_enabled", default: false)

    /// Davet-arkadaş (referral) giriş kartı görünürlüğü. VARSAYILAN KAPALI: RWD-07 istemci soyutlaması
    /// (port + model + UI) ships, ama canlı `/rewards/referral` endpoint'i + ürün/ekonomi kararı hazır
    /// olana dek kullanıcıya GİZLİ (rewarded ad kartı precedent'i). PREP-BEKLEYEN kaleminde açılır.
    public static let referralCard = FlagKey(name: "rewards.referral_card_enabled", default: false)
}
