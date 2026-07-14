import Foundation
import Testing
@testable import WalletKit

/// appAccountToken üretimi (06 §4.3): deterministik UUIDv5 — aynı userId aynı token verir,
/// böylece misafir → hesap bağlama sonrası cüzdan korunur.
struct AppAccountTokenTests {
    @Test func ayniUserIdAyniTokenUretir() {
        let first = AppAccountToken.token(forUserID: "usr_123")
        let second = AppAccountToken.token(forUserID: "usr_123")

        #expect(first == second)
    }

    @Test func farkliUserIdFarkliTokenUretir() {
        let first = AppAccountToken.token(forUserID: "usr_123")
        let second = AppAccountToken.token(forUserID: "usr_456")

        #expect(first != second)
    }

    @Test func uuidV5SurumVeVariantBitleriDogru() {
        let token = AppAccountToken.token(forUserID: "usr_789")
        let bytes = withUnsafeBytes(of: token.uuid) { Array($0) }

        // Sürüm nibble = 5 (RFC 4122 §4.3).
        #expect((bytes[6] & 0xF0) == 0x50)
        // Variant = 10xx.
        #expect((bytes[8] & 0xC0) == 0x80)
    }
}
