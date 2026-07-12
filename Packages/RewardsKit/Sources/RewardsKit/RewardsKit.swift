import AppFoundation
import DesignSystem
import AnalyticsKit

/// RewardsKit — OdulMerkezi: günlük check-in, görevler, rewarded ads köprüsü (KANON §4).
/// F1 kapsamı: SS-110…SS-112 (docs/09 §E10); rewarded ads SS-113…SS-115 F2.
/// Reklam SDK'sı (aktif: AdMob) R6 gereği bu modülde/AdBridge'de hapsolur.
/// ContentKit'e BAĞIMLI DEĞİLDİR (R3).
public enum RewardsKitModule {
    public static let name = "RewardsKit"
}
