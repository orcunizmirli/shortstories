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
}

/// Keychain soyutlaması (03 §9): access/refresh token, anonim hesap kimliği saklar;
/// büyük veri ve tercihler BURAYA GİRMEZ. F0'da STUB — canlı Keychain uygulaması
/// SS-021'de gelir (kSecAttrAccessible: afterFirstUnlockThisDeviceOnly).
/// Uygulamalar hataları `AppError.storage(.keychainUnavailable)` olarak fırlatır.
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
