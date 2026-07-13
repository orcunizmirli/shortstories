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
}
