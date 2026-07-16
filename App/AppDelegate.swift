import AppFoundation
import UIKit
import UserNotifications

/// UIKit yaşam döngüsü + APNs/UN köprüsü (`UIApplicationDelegateAdaptor`). SS-140/143: bildirim izni
/// İSTENMEZ (Onboarding'de, değer önerisinden sonra — kanon §3); bu tip yalnız kayıt/teslim/dokunma
/// callback'lerini `PushService`'e akıtır. UN/UIKit tipleri BU seam'in dışına çıkmaz (03 §10.1) —
/// `PushService` yalnız `Data` + `PushPayload` (Sendable değer tipi) görür.
///
/// Bağlama sırası: `AppDelegate`, kompozisyon kökünden (`ShortSeriesApp`) ÖNCE kurulabilir → `pushService`
/// bağlanana kadar gelen callback'ler tamponlanır ve bağlanınca boşaltılır (soğuk açılış push'u kaybolmaz).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Kompozisyon kökü (`ShortSeriesApp.task`) bağlar. Bağlanınca tampon boşaltılır.
    var pushService: PushService? {
        didSet { drainBuffer() }
    }

    /// `pushService` henüz yokken gelen APNs token'ı (kayıt callback'i erken gelebilir). `Data` Sendable.
    private var bufferedTokenData: Data?
    /// `pushService` henüz yokken gelen açılış-push'u (dokunma callback'i attach'tan önce gelebilir).
    private var bufferedOpenedPayload: PushPayload?

    private let logger = OSLogger(category: "Push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // UN delegate: foreground sunum + dokunma callback'leri buraya gelsin. Soğuk açılış bir push'a
        // dokunularak yapıldıysa sistem yine `userNotificationCenter(_:didReceive:)`i (delegate atandıktan
        // sonra) çağırır → oradan `PushService` → soğuk açılışta `LaunchCoordinator` PendingRoute (02 §5.6).
        UNUserNotificationCenter.current().delegate = self
        // SS-141 rich push: kategori + aksiyon butonlarını kaydet. Kimlikler NSE'nin
        // `content.categoryIdentifier`e yazdığıyla AYNIDIR (`RichPushCategory`) → butonlar eşleşir.
        // İzinden bağımsızdır (kayıt, bildirim gösterildiğinde aksiyonların çözülebilmesi içindir).
        UNUserNotificationCenter.current().setNotificationCategories(Self.richPushCategories())
        return true
    }

    /// Saf `RichPushCategory.all` tanımlarını UN tiplerine köprüler (UN tipleri saf çekirdeğe sızmasın diye
    /// çeviri BURADA yapılır). Aksiyonu olan tek buton foreground'dur (dokununca uygulama açılır → deep link).
    private static func richPushCategories() -> Set<UNNotificationCategory> {
        Set(RichPushCategory.all.map { descriptor in
            let actions = descriptor.actions.map { action in
                UNNotificationAction(
                    identifier: action.identifier,
                    title: action.title,
                    options: action.opensApp ? [.foreground] : []
                )
            }
            return UNNotificationCategory(
                identifier: descriptor.identifier,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
        })
    }

    // MARK: - APNs kayıt sonucu

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        if let pushService {
            pushService.didRegisterToken(deviceToken)
        } else {
            bufferedTokenData = deviceToken
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Retry stratejisi yok (bir sonraki launch/foreground yeniden dener). PII kuralı: hata gövdesi
        // loglanmaz — yalnız akış kilometre taşı.
        logger.error("push: APNs kaydı başarısız")
    }

    // MARK: - Sessiz/arka plan push (content-available) — F1'de navigasyon YOK

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // F1'de sessiz push ile içerik çekme yok; navigasyon YALNIZ kullanıcı dokunmasıyla
        // (`userNotificationCenter(_:didReceive:)`) olur → burada içerik yok döner.
        completionHandler(.noData)
    }

    // MARK: - Tampon boşaltma / teslim (main-actor)

    /// Açılan push'u teslim eder (dokunma callback'inden main-actor Task ile çağrılır). Attach edilmemişse
    /// tamponlar (Sendable `PushPayload`).
    fileprivate func deliverOpenedPush(_ payload: PushPayload) {
        if let pushService {
            pushService.handleOpenedPush(payload)
        } else {
            bufferedOpenedPayload = payload
        }
    }

    private func drainBuffer() {
        guard let pushService else { return }
        if let data = bufferedTokenData {
            bufferedTokenData = nil
            pushService.didRegisterToken(data)
        }
        if let payload = bufferedOpenedPayload {
            bufferedOpenedPayload = nil
            pushService.handleOpenedPush(payload)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate (dokunma + foreground sunum)

/// UN delegate metotları `nonisolated` sözleşmedir ama sistem bunları ANA THREAD'de çağırır. Ham UN
/// tipini main-actor'a GÖNDERMEMEK için payload nonisolated bağlamda Sendable `PushPayload`'a çözülür,
/// yalnız o değer main-actor Task'ine geçirilir (Swift 6 strict concurrency; F1/bilinmeyen tip → nil).
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Kullanıcı push'a dokundu (foreground/background/soğuk açılış fark etmeksizin, delegate atandıktan
    /// sonra). Payload nonisolated çözülür; çözülürse main-actor'da `PushService`'e teslim edilir.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        if let payload {
            Task { @MainActor in self.deliverOpenedPush(payload) }
        }
        completionHandler()
    }

    /// Foreground'da bildirim geldiğinde sunum davranışı: banner + ses (kullanıcı uygulama açıkken de
    /// yeni bölüm/devam-et bildirimini görür). Rozet F1'de yönetilmez.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
