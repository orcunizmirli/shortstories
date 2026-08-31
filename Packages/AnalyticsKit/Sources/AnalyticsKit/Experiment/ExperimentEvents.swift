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
    /// parametresi backend'de sessizce düşerdi (audit LOW). Aşan bir girdi ATLANIR (`continue`) ve
    /// sıralamada SONRAKİ sığabilecek (kısa) atamalar korunur — `break` sonraki kısa atamaları da düşürüp
    /// o deneyi ab_variants'tan eksik bırakırdı.
    public static func format(_ assignments: [String: String]) -> String {
        var result = ""
        for (key, value) in assignments.sorted(by: { $0.key < $1.key }) {
            // Delimiter injection savunması: key/value `:` ya da `,` içerirse (bozuk remote config) düzleştirilmiş
            // string ambiguous olur (backend yanlış pair'lere böler) → o girdiyi ATLA (diğer deneylerin
            // pair'lerini bozmasın; ambiguous pair yaymaktan iyidir). Key'ler/id'ler konvansiyonel snake_case.
            guard !key.contains(where: Self.isDelimiter), !value.contains(where: Self.isDelimiter) else { continue }
            let entry = "\(key):\(value)"
            let candidate = result.isEmpty ? entry : "\(result),\(entry)"
            if candidate.count > maxLength {
                continue
            }
            result = candidate
        }
        return result
    }

    /// `ab_variants` düzleştirme delimiterları — key/value bunlardan birini içerirse pair ambiguous olur.
    private static func isDelimiter(_ character: Character) -> Bool {
        character == ":" || character == ","
    }
}
