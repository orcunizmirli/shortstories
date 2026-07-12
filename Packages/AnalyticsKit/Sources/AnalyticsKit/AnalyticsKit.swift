import AppFoundation

/// AnalyticsKit — event şeması ve A/B deney istemcisi (KANON §4).
/// F1 kapsamı: SS-150, SS-152, SS-153, SS-156 (docs/09 §E14); A/B istemcisi SS-154/155 F2.
/// Firebase Analytics/Crashlytics R6 gereği bu modülde hapsolur; `AnalyticsTracking`
/// protokolünün canlı implementasyonu F1'de burada yazılır.
public enum AnalyticsKitModule {
    public static let name = "AnalyticsKit"
}
