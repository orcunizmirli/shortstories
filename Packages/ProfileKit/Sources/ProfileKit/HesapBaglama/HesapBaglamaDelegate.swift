/// Hesap bağlama ekranı navigasyon niyetleri (SS-132) — App koordinatörü bağlar. Oturum yükseltme
/// (misafir→bağlı) `AccountLinkingServicing` portunun App-tarafı implementasyonunda `SessionManager`
/// ile yapılır; bu delegate yalnız ekranın SONRASINI (kapan/köke dön) yönetir. Zayıf referans, MainActor.
@MainActor
public protocol HesapBaglamaDelegate: AnyObject {
    /// Bağlama başarılı (doğrudan veya "mevcut hesaba geç" ile) → oturum bağlıya yükseldi.
    /// App ekranı kapatır ve kök akışı (Profil/feed) güncel kimlikle tazeler.
    func hesapBaglamaDidLink(_ account: AccountSummary)

    /// Kullanıcı ekranı bağlamadan kapattı.
    func hesapBaglamaRequestsDismiss()
}
