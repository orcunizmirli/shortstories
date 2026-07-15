/// Uygulama arayüz dili tercihi (SS-161) — altyazı dilinden BAĞIMSIZ değer tipi. Kalıcı temsili
/// BCP-47 birincil alt-etiketidir (ör. "en", "tr"). Uygulama dili YALNIZ paketlenmiş/desteklenen
/// bir dil olabilir (bkz. `LanguageCatalog.supportedAppLanguages`); bilinmeyen kod varsayılana
/// (`.default`) düşer. Değişim yeniden başlatma gerektirmez (02 §4.14: SwiftUI locale environment
/// yeniden inject edilir) — App bunu `AppLanguageProviding` üzerinden okur.
public struct AppLanguage: Sendable, Equatable, Hashable, Identifiable {
    /// BCP-47 birincil alt-etiket.
    public let code: String

    public var id: String {
        code
    }

    public init(code: String) {
        self.code = code
    }

    public static let english = AppLanguage(code: "en")
    public static let turkish = AppLanguage(code: "tr")
    public static let spanish = AppLanguage(code: "es")
    public static let portuguese = AppLanguage(code: "pt")

    /// Kanonik varsayılan (kanon §1: EN başta).
    public static let `default` = AppLanguage.english

    /// Dilin kendi adı (endonym) — dil seçici her dili KENDİ adıyla gösterir (locale-bağımsız).
    public var displayName: String {
        LanguageCatalog.endonym(forCode: code)
    }
}
