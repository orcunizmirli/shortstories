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

    /// Firebase/GA4 string-parametre uzunluk sınırı (aşan değer sessizce düşürülür/kesilir).
    static let maxLength = 100

    /// `experimentKey -> variantID` haritasını kanonik düzleştirilmiş string'e çevirir.
    /// Deterministik: anahtara göre sıralı, `"a:v1,b:control"` biçimi. 100 karakteri aşarsa (çok deney)
    /// yalnız TAM sığan atamalar dahil edilir (yarım variant yok) — aksi halde tüm `ab_variants`
    /// parametresi backend'de sessizce düşerdi (audit LOW).
    public static func format(_ assignments: [String: String]) -> String {
        var result = ""
        for (key, value) in assignments.sorted(by: { $0.key < $1.key }) {
            let entry = "\(key):\(value)"
            let candidate = result.isEmpty ? entry : "\(result),\(entry)"
            if candidate.count > maxLength {
                break
            }
            result = candidate
        }
        return result
    }
}
