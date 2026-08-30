import Foundation

/// Keychain kayıtları için tip-güvenli anahtar sarmalayıcı.
public struct SecureStoreKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let accessToken = SecureStoreKey(rawValue: "auth.accessToken")
    public static let refreshToken = SecureStoreKey(rawValue: "auth.refreshToken")
    public static let guestAccountID = SecureStoreKey(rawValue: "auth.guestAccountID")
    /// Cihaz başına bir kez üretilen kalıcı kimlik; `POST /auth/guest` gövdesindeki `deviceId`.
    /// Reinstall'da devam kanonu bu anahtara dayanır (05 §4.2).
    public static let deviceID = SecureStoreKey(rawValue: "auth.deviceID")
    /// Oturum kimliği snapshot'ı (`StoredSessionSnapshot` JSON'u): userID + bağlama sağlayıcısı.
    public static let sessionSnapshot = SecureStoreKey(rawValue: "auth.sessionSnapshot")
    /// En son sunucuya gönderilen APNs kayıt snapshot'ı (`DeviceRegistrationSnapshot` JSON'u):
    /// token + izin durumu (SS-140 idempotent kayıt kararı). Token PII değeri Keychain'de tutulur
    /// (UserDefaults'a token YAZILMAZ — PreferencesStoring sözleşmesi).
    public static let pushRegistration = SecureStoreKey(rawValue: "push.registrationSnapshot")
}

/// Keychain soyutlaması (03 §9): access/refresh token, anonim hesap kimliği saklar;
/// büyük veri ve tercihler BURAYA GİRMEZ. Canlı uygulama: `KeychainSecureStore`
/// (kSecAttrAccessible: afterFirstUnlockThisDeviceOnly — 03 §9 birebir; reinstall'da
/// devam kanonu korunur, yalnız yedek/iCloud ile başka cihaza taşınma engellenir —
/// `deviceId` fraud sinyalidir). Uygulamalar hataları
/// `AppError.storage(.keychainUnavailable)` olarak fırlatır.
public protocol SecureStoring: Sendable {
    func data(forKey key: SecureStoreKey) throws -> Data?
    func setData(_ data: Data, forKey key: SecureStoreKey) throws
    func removeData(forKey key: SecureStoreKey) throws
}

public extension SecureStoring {
    func string(forKey key: SecureStoreKey) throws -> String? {
        try data(forKey: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    func setString(_ value: String, forKey key: SecureStoreKey) throws {
        try setData(Data(value.utf8), forKey: key)
    }

    /// Birden çok anahtarı ATOMİK yazar (best-effort): önce mevcut değerler yedeklenir, sonra tümü yazılır;
    /// HERHANGİ biri koparsa YEDEKLERE geri alınır → keychain "torn" (yarı-yazılmış) durumda KALMAZ (ya
    /// hepsi-yeni ya hepsi-eski). Native Keychain transaction YOK; rollback yazması da koparsa (nadir) tam
    /// garanti değildir, ama yaygın torn-write'ı (linkSession snapshot↔token ayrışması) engeller. Anahtarlar
    /// AYRI kalır (okuyucular değişmez); yalnız yazım atomikleşir.
    func setAtomically(_ writes: [(key: SecureStoreKey, data: Data)]) throws {
        var previous: [(key: SecureStoreKey, data: Data?)] = []
        previous.reserveCapacity(writes.count)
        for (key, _) in writes {
            previous.append((key, try? data(forKey: key)))
        }
        do {
            for (key, value) in writes {
                try setData(value, forKey: key)
            }
        } catch {
            for (key, prev) in previous {
                if let prev {
                    try? setData(prev, forKey: key)
                } else {
                    try? removeData(forKey: key)
                }
            }
            throw error
        }
    }
}
