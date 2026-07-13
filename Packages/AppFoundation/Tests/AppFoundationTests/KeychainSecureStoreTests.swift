import Foundation
import Security
import Testing
@testable import AppFoundation

// MARK: - In-memory securityd taklidi

/// `SecItem*` semantiğini (duplicate, notFound, accessibility attribute'u) birebir taklit eder.
/// Hostsuz SPM paket testlerinde securityd erişimi yoktur (errSecMissingEntitlement, -34018);
/// davranış testleri bu taklitle, canlı Keychain testleri `KeychainSecureStoreLiveTests`'te koşar.
private final class FakeKeychain: KeychainInterfacing, @unchecked Sendable {
    struct ItemKey: Hashable {
        let service: String
        let account: String
    }

    struct Item {
        var data: Data
        var accessible: String?
    }

    private let lock = NSLock()
    private var items: [ItemKey: Item] = [:]
    private var forced: OSStatus?
    private var receivedClasses: [String] = []

    var storedItems: [ItemKey: Item] {
        lock.withLock { items }
    }

    var receivedItemClasses: [String] {
        lock.withLock { receivedClasses }
    }

    func forceStatus(_ status: OSStatus?) {
        lock.withLock { forced = status }
    }

    private func fields(of dictionary: CFDictionary) -> [String: Any] {
        (dictionary as NSDictionary) as? [String: Any] ?? [:]
    }

    private func itemKey(of fields: [String: Any]) -> ItemKey {
        ItemKey(
            service: fields[kSecAttrService as String] as? String ?? "",
            account: fields[kSecAttrAccount as String] as? String ?? ""
        )
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        let fields = fields(of: attributes)
        return lock.withLock {
            if let itemClass = fields[kSecClass as String] as? String {
                receivedClasses.append(itemClass)
            }
            if let forced {
                return forced
            }
            let key = itemKey(of: fields)
            if items[key] != nil {
                return errSecDuplicateItem
            }
            guard let data = fields[kSecValueData as String] as? Data else {
                return errSecParam
            }
            items[key] = Item(data: data, accessible: fields[kSecAttrAccessible as String] as? String)
            return errSecSuccess
        }
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        let queryFields = fields(of: query)
        let attributeFields = fields(of: attributes)
        return lock.withLock {
            if let forced {
                return forced
            }
            let key = itemKey(of: queryFields)
            guard var item = items[key] else {
                return errSecItemNotFound
            }
            if let data = attributeFields[kSecValueData as String] as? Data {
                item.data = data
            }
            if let accessible = attributeFields[kSecAttrAccessible as String] as? String {
                item.accessible = accessible
            }
            items[key] = item
            return errSecSuccess
        }
    }

    func copyMatching(_ query: CFDictionary, _ result: inout CFTypeRef?) -> OSStatus {
        let queryFields = fields(of: query)
        return lock.withLock {
            if let forced {
                return forced
            }
            guard let item = items[itemKey(of: queryFields)] else {
                return errSecItemNotFound
            }
            if queryFields[kSecReturnData as String] as? Bool == true {
                result = item.data as CFTypeRef
            }
            return errSecSuccess
        }
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let queryFields = fields(of: query)
        return lock.withLock {
            if let forced {
                return forced
            }
            let key = itemKey(of: queryFields)
            guard items[key] != nil else {
                return errSecItemNotFound
            }
            items[key] = nil
            return errSecSuccess
        }
    }
}

// MARK: - Davranış testleri (in-memory taklit)

struct KeychainSecureStoreTests {
    private let keychain = FakeKeychain()
    private let store: KeychainSecureStore

    init() {
        store = KeychainSecureStore(service: "com.shortseries.app.tests", keychain: keychain)
    }

    private func item(for key: SecureStoreKey) -> FakeKeychain.Item? {
        keychain.storedItems[.init(service: "com.shortseries.app.tests", account: key.rawValue)]
    }

    @Test func varsayilanServiceKanonikBundleKimligidir() {
        #expect(KeychainSecureStore().service == "com.shortseries.app")
    }

    @Test func genericPasswordSinifiylaYazar() throws {
        try store.setData(Data("x".utf8), forKey: .accessToken)

        #expect(keychain.receivedItemClasses == [kSecClassGenericPassword as String])
    }

    @Test func yazilanVeriGeriOkunur() throws {
        let payload = Data("token-123".utf8)
        try store.setData(payload, forKey: .accessToken)

        #expect(try store.data(forKey: .accessToken) == payload)
    }

    @Test func olmayanAnahtarNilDoner() throws {
        #expect(try store.data(forKey: .refreshToken) == nil)
    }

    @Test func mevcutAnahtaraYazmakUzerineYazar() throws {
        try store.setData(Data("eski".utf8), forKey: .accessToken)
        try store.setData(Data("yeni".utf8), forKey: .accessToken)

        #expect(try store.data(forKey: .accessToken) == Data("yeni".utf8))
    }

    @Test func silinenAnahtarNilDoner() throws {
        try store.setData(Data("silinecek".utf8), forKey: .accessToken)
        try store.removeData(forKey: .accessToken)

        #expect(try store.data(forKey: .accessToken) == nil)
    }

    @Test func olmayanAnahtariSilmekHataFirlatmaz() throws {
        try store.removeData(forKey: .guestAccountID)
    }

    @Test func anahtarlarBirbirindenIzoledir() throws {
        try store.setData(Data("access".utf8), forKey: .accessToken)
        try store.setData(Data("refresh".utf8), forKey: .refreshToken)

        try store.removeData(forKey: .accessToken)

        #expect(try store.data(forKey: .accessToken) == nil)
        #expect(try store.data(forKey: .refreshToken) == Data("refresh".utf8))
    }

    @Test func stringUzantisiRoundTripYapar() throws {
        try store.setString("rt_8Kj2", forKey: .refreshToken)

        #expect(try store.string(forKey: .refreshToken) == "rt_8Kj2")
    }

    @Test func kayitlarAfterFirstUnlockThisDeviceOnlyErisilebilirligiyleSaklanir() throws {
        // 03 §9 birebir: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. ThisDeviceOnly
        // reinstall'da hayatta kalır (KANON §2 devam kanunu bozulmaz); yalnız yedek/iCloud ile
        // başka cihaza taşınmayı engeller — deviceId (X-Device-Id) fraud sinyalidir.
        try store.setData(Data("token".utf8), forKey: .accessToken)

        #expect(item(for: .accessToken)?.accessible
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func uzerineYazmaErisilebilirligiKorur() throws {
        try store.setData(Data("ilk".utf8), forKey: .accessToken)
        try store.setData(Data("ikinci".utf8), forKey: .accessToken)

        #expect(item(for: .accessToken)?.accessible
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func keychainHatasiKeychainUnavailableOlarakEslenir() throws {
        try store.setData(Data("x".utf8), forKey: .accessToken)
        keychain.forceStatus(errSecInteractionNotAllowed)

        #expect(throws: AppError.storage(.keychainUnavailable)) {
            _ = try store.data(forKey: .accessToken)
        }
        #expect(throws: AppError.storage(.keychainUnavailable)) {
            try store.setData(Data("y".utf8), forKey: .accessToken)
        }
        #expect(throws: AppError.storage(.keychainUnavailable)) {
            try store.removeData(forKey: .accessToken)
        }
    }
}

// MARK: - Canlı Keychain testleri

private let liveTestService = "com.shortseries.app.tests.live"

private var liveKeychainAvailable: Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: liveTestService,
        kSecAttrAccount as String: "probe"
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
}

/// Gerçek simülatör Keychain'ine yazar ve temizler. Hostsuz SPM test koşucusunda securityd
/// erişimi olmadığından (errSecMissingEntitlement) atlanır; test host'lu ortamda otomatik koşar.
@Suite(.serialized, .enabled(if: liveKeychainAvailable))
struct KeychainSecureStoreLiveTests {
    private static let testService = liveTestService
    private let store = KeychainSecureStore(service: Self.testService)

    init() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.testService
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test func yazilanVeriGeriOkunurVeTemizlenir() throws {
        let payload = Data("live-token".utf8)
        try store.setData(payload, forKey: .accessToken)

        #expect(try store.data(forKey: .accessToken) == payload)

        try store.removeData(forKey: .accessToken)
        #expect(try store.data(forKey: .accessToken) == nil)
    }

    @Test func kayitlarAfterFirstUnlockThisDeviceOnlyErisilebilirligiyleSaklanir() throws {
        try store.setData(Data("live".utf8), forKey: .accessToken)
        defer { try? store.removeData(forKey: .accessToken) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.testService,
            kSecAttrAccount as String: SecureStoreKey.accessToken.rawValue,
            kSecReturnAttributes as String: true
        ]
        var attributesRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &attributesRef)

        #expect(status == errSecSuccess)
        let accessible = (attributesRef as? [String: Any])?[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
}
