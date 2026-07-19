/// `BildirimMerkezi` navigasyon niyetleri (NTF-04; 02 §4.15). App koordinatörü bağlar. ProfileKit
/// DiscoverKit/Route enum'unu GÖRMEDİĞİNDEN rotayı ham String taşır; çözüm + geçersiz-hedef
/// fallback'i App'te `Route(url:)`/`DeepLinkResolver`'dadır (§8.4). Zayıf referans, MainActor.
@MainActor
public protocol NotificationCenterDelegate: AnyObject {
    /// Satır dokunuşu → bildirimin `route`'u push ile AYNI deep link olarak açılır (NTF-04 kabul
    /// kriteri). App `Route(url:)` ile çözer; hedef artık geçersizse (dizi kaldırıldı) App KENDİ
    /// `Kesfet` fallback'ini uygular (§8.4 kural 3/4). Model rotayı yalnız İLETİR, çözmez.
    func notificationCenterOpensRoute(_ route: String)

    /// Bildirim YAPISAL olarak geçersiz rota taşıyor (boş/eksik) → doğrudan `Kesfet` fallback
    /// (02 §4.15 geçersiz-hedef + §8.4 kuralı; App'in Route çözümüne bile gitmeden ayrıştırılır).
    func notificationCenterFallsBackToDiscover()
}
