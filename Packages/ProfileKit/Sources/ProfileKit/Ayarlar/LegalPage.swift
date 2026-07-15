/// Ayarlar → Yasal grubu sayfaları (02 §4.14: Şartlar, Gizlilik, Açık kaynak lisansları;
/// SS-175: ToS/Privacy/EULA). App bir link/webview açar (URL'ler App/remote config'te).
public enum LegalPage: String, Sendable, CaseIterable, Equatable, Hashable {
    /// Kullanım Koşulları (ToS).
    case termsOfService
    /// Gizlilik Politikası.
    case privacyPolicy
    /// EULA (App Store standart / özel — earned coin son kullanma + kapalı-devre maddeleri).
    case eula
    /// Açık kaynak lisansları.
    case openSourceLicenses
}
