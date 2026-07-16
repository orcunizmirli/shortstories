import Foundation

/// APNs cihaz token'ının uygulama-alanı değer tipi (SS-140). Ham `Data` → hex dönüşümü TEK noktada
/// yapılır; `UNUserNotificationCenter`/`UIApplication` tipleri public API'ye SIZMAZ — bu tip yalnız
/// hex `String` taşır ve `didRegisterForRemoteNotificationsWithDeviceToken` `Data`'sı App delegate
/// seam'inde bu tipe çevrilir (03 §10.1 katman sınırı).
public struct DeviceToken: Sendable, Equatable {
    /// APNs token'ının hex string gösterimi (05 §4.9 POST /devices `apnsToken`).
    public let hexString: String

    public init(hexString: String) {
        self.hexString = hexString
    }

    /// `didRegisterForRemoteNotificationsWithDeviceToken` `Data`'sını hex'e çevirir
    /// (küçük harf, byte başına 2 hane) — APNs token'ının kanonik string biçimi.
    public init(rawTokenData: Data) {
        hexString = rawTokenData.map { String(format: "%02x", $0) }.joined()
    }
}
