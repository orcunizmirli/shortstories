import Foundation
import Security

/// `SecItem*` çağrılarının dar soyutlaması. Hostsuz SPM paket testleri simülatörde
/// securityd'ye erişemediği için (errSecMissingEntitlement) davranış testleri bu seam
/// üzerinden in-memory taklitle koşar; canlı uygulama `SystemKeychain` kullanır.
protocol KeychainInterfacing: Sendable {
    func add(_ attributes: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: inout CFTypeRef?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychain: KeychainInterfacing {
    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func copyMatching(_ query: CFDictionary, _ result: inout CFTypeRef?) -> OSStatus {
        SecItemCopyMatching(query, &result)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

/// `SecureStoring`'in canlı Keychain uygulaması (`kSecClassGenericPassword`).
/// Erişilebilirlik `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`dir (03 §9 birebir):
/// ThisDeviceOnly reinstall'da hayatta kalır — devam kanonu (KANON §2: sunucu aynı
/// `deviceId` için mevcut misafir hesabını döndürür) bozulmaz; yalnız yedek/iCloud ile
/// BAŞKA cihaza taşınmayı engeller. `deviceId` fraud sinyalidir (`X-Device-Id`), cihaza
/// bağlı kalmak zorundadır. Keychain hataları `AppError.storage(.keychainUnavailable)`
/// olarak yüzer.
public struct KeychainSecureStore: SecureStoring {
    let service: String
    private let keychain: any KeychainInterfacing

    public init(service: String = "com.shortseries.app") {
        self.init(service: service, keychain: SystemKeychain())
    }

    init(service: String, keychain: any KeychainInterfacing) {
        self.service = service
        self.keychain = keychain
    }

    public func data(forKey key: SecureStoreKey) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw AppError.storage(.keychainUnavailable)
        }
    }

    public func setData(_ data: Data, forKey key: SecureStoreKey) throws {
        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        switch keychain.add(addQuery as CFDictionary) {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Erişilebilirlik attribute'u da güncellenir — eski kayıtlar kanona çekilir.
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let status = keychain.update(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw AppError.storage(.keychainUnavailable)
            }
        default:
            throw AppError.storage(.keychainUnavailable)
        }
    }

    public func removeData(forKey key: SecureStoreKey) throws {
        let status = keychain.delete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.storage(.keychainUnavailable)
        }
    }

    private func baseQuery(for key: SecureStoreKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
