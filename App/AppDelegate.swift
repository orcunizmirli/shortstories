import UIKit

/// UIKit yaşam döngüsü köprüsü (`UIApplicationDelegateAdaptor`).
/// F0'da yalnız APNs kayıt hook'larının iskeleti — push kaydı SS-140+ kapsamındadır;
/// bildirim izni İSTENMEZ (Onboarding'de, değer önerisinden sonra — kanon §3).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // TODO(SS-140): UNUserNotificationCenter delegate kurulumu + kategori kayıtları.
        true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // TODO(SS-140): device token'ı backend'e kaydet (POST /devices).
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // TODO(SS-140): kayıt hatasını OSLogger("App") ile logla; retry stratejisi yok (bir sonraki launch).
    }
}
