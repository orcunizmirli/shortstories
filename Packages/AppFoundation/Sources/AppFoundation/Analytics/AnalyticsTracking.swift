/// Type-erased analitik parametre değeri (03 §5.1).
public enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

/// Type-erased analitik arayüzü (03 §5.1). Canlı uygulama `AnalyticsKit.AnalyticsClient`'tır
/// (F1); tipli `AnalyticsEvent` yüzeyi (event kataloğu, parametre şemaları —
/// 08-analitik-deney.md) `AnalyticsKit`'te kalır ve çağrı anında bu protokole map edilir.
public protocol AnalyticsTracking: Sendable {
    func track(_ name: String, parameters: [String: AnalyticsValue])
}
