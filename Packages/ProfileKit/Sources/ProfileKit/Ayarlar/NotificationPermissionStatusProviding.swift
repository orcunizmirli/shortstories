/// Sistem bildirim izni durumu OKUMA portu (SS-140; 02 §4.14). App `UNUserNotificationCenter`'a
/// bağlar (üretici); `AyarlarModel` ana bildirim anahtarı AÇILIRKEN bu izni kontrol eder ve izin
/// kapalıysa uygulama-içi anahtarı açmak yerine sistem Ayarlar'a yönlendirir (uygulama-içi anahtar
/// sistem izni olmadan etkisizdir). Senkron okuma: App en son bilinen yetki durumunu (foreground'da
/// tazelenen) sunar — model kararı @MainActor'da senkron kalır, View binding'i basit tutulur.
public protocol NotificationPermissionStatusProviding: Sendable {
    /// Kullanıcı sistem düzeyinde bildirime izin verdi mi (anlık, cache'lenmiş okuma).
    var isSystemNotificationPermissionGranted: Bool { get }
}
