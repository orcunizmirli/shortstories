/// Deney analitik sözleşmesi — event ve parametre adları docs/08 §7.3 registry'siyle
/// BİREBİR aynıdır. Değişiklik önce dokümanı + registry'yi güncellemeyi gerektirir.
enum ExperimentEvent {
    /// Varyant davranışı İLK KEZ tetiklendiğinde (atama anında DEĞİL, §7.3).
    static let exposure = "ab_exposure"

    enum Param {
        static let experimentKey = "exp_key"
        static let variant = "variant"
        static let firstExposure = "first_exposure"
    }
}

/// Tüm event'lerde taşınan ortak deney boyutu (docs/08 §1.3, §7.3): aktif atamalar
/// `"exp_key:variant"` çiftlerinin virgülle düzleştirilmiş tek string'i.
public enum ABVariants {
    /// Ortak parametre anahtarı (`ab_variants`).
    public static let parameterKey = "ab_variants"

    /// `experimentKey -> variantID` haritasını kanonik düzleştirilmiş string'e çevirir.
    /// Deterministik: anahtara göre sıralı, `"a:v1,b:control"` biçimi.
    public static func format(_ assignments: [String: String]) -> String {
        assignments
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
}
