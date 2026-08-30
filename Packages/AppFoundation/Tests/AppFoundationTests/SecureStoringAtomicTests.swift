import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing

/// `SecureStoring.setAtomically` (audit MEDIUM linkSession atomiklik primitifi): birden çok anahtarı
/// yazarken HERHANGİ biri koparsa TÜMÜ yedeklere geri alınır → keychain torn (yarı-yazılmış) kalmaz.
@Suite("SecureStoring.setAtomically rollback")
struct SecureStoringAtomicTests {
    @Test func tumuBasarilıysaHepsiYazilir() throws {
        let store = MockSecureStore()
        try store.setAtomically([
            (.accessToken, Data("a".utf8)),
            (.refreshToken, Data("r".utf8))
        ])
        #expect(try store.string(forKey: .accessToken) == "a")
        #expect(try store.string(forKey: .refreshToken) == "r")
    }

    @Test func herhangiBiriKoparsaTumuGeriAlinir() throws {
        // İkinci yazma (accessToken) kopar → ilk yazma (refreshToken) ESKİ değerine geri alınır;
        // access (önceden yoktu) kaldırılır → hepsi-eski tutarlı hal (torn YOK).
        let store = WriteFailingSecureStore(failWriteFor: .accessToken)
        try store.backing.setString("old-refresh", forKey: .refreshToken)
        store.arm()

        #expect(throws: (any Error).self) {
            try store.setAtomically([
                (.refreshToken, Data("new-refresh".utf8)), // yazılır
                (.accessToken, Data("new-access".utf8)) // KOPAR
            ])
        }

        #expect(try store.string(forKey: .refreshToken) == "old-refresh") // geri alındı
        #expect(try store.data(forKey: .accessToken) == nil) // önceden yoktu → kaldırıldı
    }
}
