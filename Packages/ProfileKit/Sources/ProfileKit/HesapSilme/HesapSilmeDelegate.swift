/// Hesap silme ekranı navigasyon niyetleri (SS-133) — App koordinatörü bağlar. Silme tamamlanınca
/// oturum sıfırlama (yeni misafir bootstrap) + köke dönüş App'tedir (kanon: `SessionState` mutasyonu
/// `SessionManager`'da). Zayıf referans, MainActor.
@MainActor
public protocol HesapSilmeDelegate: AnyObject {
    /// Silme talebi alındı/planlandı → App yeni misafir oturumu açar ve köke döner (ONB-07 KC1).
    /// `receipt` geri-alma penceresi/abonelik uyarısını taşır (App bilgi ekranında da gösterebilir).
    func hesapSilmeDidComplete(_ receipt: AccountDeletionReceipt)

    /// Kullanıcı ekranı silmeden kapattı.
    func hesapSilmeRequestsDismiss()
}
