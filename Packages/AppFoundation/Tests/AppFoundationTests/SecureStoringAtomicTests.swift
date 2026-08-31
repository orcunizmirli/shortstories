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

    @Test func yedekOkumasiKoparsaHicYazmadanFirlatir() throws {
        // audit LOW (self-review): yedek okuması GEÇİCİ koparsa (keychainUnavailable) eski kod `try?` ile nil
        // KAYDEDİP yazıma devam ederdi → sonraki write-fail'de rollback GERÇEK değeri SİLER. Fix: `try` yedek
        // okunamazsa HİÇ yazmadan FIRLAT (fail-safe) → mevcut değerler DEĞİŞMEZ, çağıran tekrar dener.
        let store = ReadFailingSecureStore(failReadFor: .accessToken)
        try store.backing.setString("old-refresh", forKey: .refreshToken)
        try store.backing.setString("old-access", forKey: .accessToken)
        store.arm() // bundan sonra .accessToken OKUMASI kopar

        #expect(throws: (any Error).self) {
            try store.setAtomically([
                (.refreshToken, Data("new-refresh".utf8)),
                (.accessToken, Data("new-access".utf8))
            ])
        }

        // Hiçbir yazım yapılmadı → mevcut değerler KORUNDU (yıkıcı rollback/silme YOK).
        #expect(try store.backing.string(forKey: .refreshToken) == "old-refresh")
        #expect(try store.backing.string(forKey: .accessToken) == "old-access")
    }
}
