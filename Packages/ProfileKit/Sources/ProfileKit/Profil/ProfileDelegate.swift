import AppFoundation

/// `Profil` navigasyon niyetleri — App koordinatörü bağlar (02 §4.13 akışları). WalletKit/
/// LibraryKit/PlayerKit ProfileKit'e import EDİLMEZ; hedef ekranlar (CoinMagazasi, VIPAbonelik,
/// Listem/Devam Et, hesap bağlama akışı) koordinatördedir (R2). Zayıf referans, MainActor.
@MainActor
public protocol ProfileDelegate: AnyObject {
    /// Misafir hesap kartı "Hesabını bağla" CTA → hesap bağlama akışı (SS-132; F1 Apple).
    func profileRequestsAccountLinking()

    /// Oturum düştü durumunda yeniden giriş (05 §4.2; F2 UI, misafire dönülmez).
    func profileRequestsReauthentication(provider: AuthProvider)

    /// Cüzdan satırı "Coin Al" → `CoinMagazasi` (02 §4.13).
    func profileOpensCoinStore()

    /// VIP satırı → `VIPAbonelik`; bağlıysa yönetim modu (`isSubscribed`), değilse tanıtım.
    func profileOpensVIP(isSubscribed: Bool)

    /// İzleme geçmişi satırı → `Listem`/Devam Et segmenti (sekme değişimi, 02 §4.13).
    func profileOpensWatchHistory()

    /// Ayarlar satırı → `Ayarlar` (Profil stack push; App NavigationStack'i sürer).
    func profileOpensSettings()

    /// BildirimMerkezi satırı → `BildirimMerkezi` (Faz 2; satır flag ardında).
    func profileOpensNotificationCenter()

    /// Alt bölge "Yardım/Destek" satırı → Destek/Yardım yüzeyi (02 §4.13.1).
    func profileOpensSupport()
}
