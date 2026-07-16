import UIKit
import UserNotifications

// SS-140 — APNs kayıt/izin DIŞ SİSTEM portları (kanon §2 sarmalı kalıbı). `UIApplication` (uzak
// bildirim kaydı) ve `UNUserNotificationCenter` (yetki durumu) doğrudan model'e/servis'e değil, bu
// dar portlar arkasına alınır → `PushService` ve `OnboardingModel` testleri gerçek sistem çağrısı
// OLMADAN (fake port'larla) koşar. Ham `UIApplication`/`UNUserNotificationCenter` tipi bu seam'in
// dışına ÇIKMAZ (03 §10.1). Canlı sarmalar App kompozisyon kökünde (`AppComposition`) bağlanır.

/// APNs uzak-bildirim KAYIT tetikleyicisi (SS-140). `UIApplication.registerForRemoteNotifications()`
/// sarması: Onboarding izni VERİLDİĞİNDE ve her açılışta (izin varsa) çağrılır → sistem token üretip
/// `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`ı tetikler.
@MainActor
protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications()
}

/// Sistem bildirim yetki durumu OKUMA portu (SS-140). Kayıt YALNIZ yetkiliyken tetiklenir (izin yoksa
/// kayıt yok). Async: `UNUserNotificationCenter.notificationSettings()` async'tir.
protocol NotificationAuthorizationReading: Sendable {
    func isAuthorized() async -> Bool
}

/// Canlı `UIApplication` sarması (main-actor).
@MainActor
struct LiveRemoteNotificationRegistering: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// Canlı `UNUserNotificationCenter` yetki-durumu okuyucusu. `provisional`/`ephemeral` de push teslimine
/// izin verir → yetkili sayılır.
struct LiveNotificationAuthorizationReader: NotificationAuthorizationReading {
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
