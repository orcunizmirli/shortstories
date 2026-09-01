import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// İLK `.accessToken` okumasında (performRefresh pre-read) geçici Keychain glitch'i fırlatan stub; sonraki
/// okumalar + yazımlar `backing`'e geçer.
private final class FirstAccessReadFailingStore: SecureStoring, @unchecked Sendable {
    let backing = MockSecureStore()
    private let lock = NSLock()
    private var accessReads = 0

    func data(forKey key: SecureStoreKey) throws -> Data? {
        let firstAccessRead = key == .accessToken && lock.withLock { accessReads += 1; return accessReads } == 1
        if firstAccessRead {
            throw AppError.storage(.keychainUnavailable) // pre-read glitch (rotasyon YOK)
        }
        return try backing.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: SecureStoreKey) throws {
        try backing.setData(data, forKey: key)
    }

    func removeData(forKey key: SecureStoreKey) throws {
        try backing.removeData(forKey: key)
    }
}

/// audit MEDIUM (networking-core hunt #2): `preRefreshAccess` geçici glitch'lerse (nil) + gerçek `post` okunursa
/// `nil != T` SAHTE rotasyon üretip refresh yanıtını DÜŞÜRÜP bayat token döndürüyordu → sonraki 401'de spurious
/// logout. Fix: rotasyon karşılaştırması `pre` VE `post` başarılıyken yapılır (post-read glitch-toleransıyla simetrik).
@MainActor
struct TokenRefreshPreReadGlitchTests {
    @Test func preAccessGlitchSahteRotasyonUretmezRefreshUygulanir() async throws {
        let apiClient = MockAPIClient()
        let store = FirstAccessReadFailingStore()
        try store.backing.setString("rt_old", forKey: .refreshToken)
        try store.backing.setString("at_old", forKey: .accessToken)
        try apiClient.stub("/auth/refresh", returning: ["accessToken": "at_new", "refreshToken": "rt_new"])
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: store, failureHandler: nil)

        let result = try await coordinator.refreshAccessToken()

        #expect(result == "at_new") // refresh UYGULANDI (bayat at_old DÜŞÜRÜLMEDİ, spurious logout yok)
        #expect(try store.backing.string(forKey: .accessToken) == "at_new") // rotasyonlu access yazıldı
        #expect(try store.backing.string(forKey: .refreshToken) == "rt_new") // rotasyonlu refresh yazıldı
    }
}
