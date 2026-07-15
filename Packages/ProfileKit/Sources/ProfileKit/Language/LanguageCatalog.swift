import Foundation

/// Dil listeleri + saklı kod → değer tipi çözümü (SS-161) — SAF, yan etkisiz, izole test edilir.
/// Uygulama dili izin listesine tabidir (yalnız paketlenmiş diller); altyazı dili değildir.
public enum LanguageCatalog {
    /// Desteklenen uygulama dilleri (kanon §1: EN başta; TR/ES/PT ikinci dalga). Sıra = UI sırası.
    public static let supportedAppLanguages: [AppLanguage] = [
        .english, .turkish, .spanish, .portuguese
    ]

    /// Altyazı seçicide sunulan diller — "Kapalı" ilk sırada.
    public static let offeredSubtitleLanguages: [SubtitleLanguage] = [
        .off, .english, .turkish, .spanish, .portuguese
    ]

    /// Saklı uygulama dili kodunu çözer; desteklenmeyen kod varsayılana düşer (paketlenmemiş dile
    /// UI ayarlanamaz).
    public static func appLanguage(forStoredCode code: String) -> AppLanguage {
        supportedAppLanguages.first { $0.code == code } ?? .default
    }

    /// Saklı altyazı kodunu çözer ("off" → kapalı). Kod izin listesine tabi değildir (sunucu-tanımlı
    /// track'ler); kullanıcı seçimi olduğu gibi korunur.
    public static func subtitleLanguage(forStoredCode code: String) -> SubtitleLanguage {
        SubtitleLanguage(persistedCode: code)
    }

    /// Bir dil kodunun endonym'i (dilin kendi adı) — locale-bağımsız, deterministik. Bilinen dört
    /// dil sabittir; diğerleri için `Locale` türetimine, o da yoksa ham koda düşer.
    static func endonym(forCode code: String) -> String {
        switch code {
        case "en": "English"
        case "tr": "Türkçe"
        case "es": "Español"
        case "pt": "Português"
        default: Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code
        }
    }
}
