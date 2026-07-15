/// `Ayarlar` navigasyon/sistem niyetleri — App koordinatörü bağlar (02 §4.14). Hesap yönetimi
/// (bağla/yönet), çıkış, hesap silme (server), yasal link/webview ve sistem bildirim ayarları
/// App tarafındadır (R2; oturum mutasyonu `SessionManager`'da). Zayıf referans, MainActor.
@MainActor
public protocol SettingsDelegate: AnyObject {
    /// Hesap grubu "Hesap bağla/yönet" → hesap bağlama/yönetim akışı (SS-132; F2 detay).
    func settingsOpensAccountManagement()

    /// "Çıkış yap" → misafir moduna döner (lokal veri kalır, cüzdan server'da; 02 §4.13).
    func settingsRequestsSignOut()

    /// "Hesabı sil" → yıkıcı hesap silme ekranını açar (SS-133; App Store 5.1.1(v)). Çift-onay +
    /// silme yürütme + `account_delete_*` event'leri o ekranın (`HesapSilmeModel`) sorumluluğundadır;
    /// Ayarlar yalnız yönlendirir (tek silme yolu / tek funnel sahibi).
    func settingsRequestsAccountDeletion()

    /// Yasal satır → link/webview (SS-175). App URL'i çözer.
    func settingsOpensLegalPage(_ page: LegalPage)

    /// Bildirim ana anahtarı açılmak istenip sistem izni kapalıysa → Ayarlar uygulaması
    /// (02 §4.14: "kapalıysa Ayarlar'a yönlendir").
    func settingsOpensSystemNotificationSettings()
}
