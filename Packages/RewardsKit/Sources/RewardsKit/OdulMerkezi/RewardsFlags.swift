import AppFoundation

/// RewardsKit-sahipli feature flag anahtarları (03 §11 tipli flag kalıbı). Varsayılan KODDADIR:
/// config gelmezse uygulama varsayılanla tam çalışır.
public enum RewardsFlags {
    /// Rewarded ad kartı görünürlüğü. F1'de KAPALI (yapı var, gizli); F2 SS-113 (AdMob köprüsü)
    /// açar. Kart yalnız flag açık VE doldurma varken gösterilir (SS-113 doldurma mantığı).
    public static let rewardedAdCard = FlagKey(name: "rewards.rewarded_ad_card_enabled", default: false)
}
