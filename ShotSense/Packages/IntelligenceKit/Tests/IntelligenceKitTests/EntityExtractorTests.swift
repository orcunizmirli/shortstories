import ShotCore
import Testing
@testable import IntelligenceKit

@Suite("EntityExtractor")
struct EntityExtractorTests {
    let extractor = EntityExtractor()

    private func values(_ text: String, kind: EntityKind) -> [String] {
        extractor.extract(from: text).filter { $0.kind == kind }.map(\.rawValue)
    }

    @Test("Geçerli IBAN çıkarılır")
    func extractsValidIBAN() {
        let entities = extractor.extract(from: "IBAN: TR33 0006 1005 1978 6457 8413 26")
        let iban = entities.first { $0.kind == .iban }
        #expect(iban?.normalizedValue == "TR330006100519786457841326")
    }

    @Test("Checksum'ı geçmeyen benzer dizi IBAN sayılmaz")
    func rejectsIBANLookalike() {
        // Sipariş numaraları da IBAN desenine uyabilir; checksum kapısı bunu eler.
        #expect(values("Sipariş: TR99 1234 5678 9012 3456 7890 12", kind: .iban).isEmpty)
    }

    @Test("Etiketli wifi şifresi çıkarılır")
    func extractsWifiPassword() {
        let extracted = values("Şifre: Deniz2026!", kind: .wifiPassword)
        #expect(extracted == ["Deniz2026!"])
    }

    @Test("Etiketin kendisi değer olarak alınmaz")
    func labelIsNotTheValue() {
        // "Password: password123" satırında değer "password" değil "password123" olmalı.
        let extracted = values("Password: password123", kind: .wifiPassword)
        #expect(extracted == ["password123"])
    }

    @Test("Doğrulama kodu bağlamdan çıkarılır")
    func extractsVerificationCode() {
        // 482913 tek başına anlamsız; "doğrulama kodu" etiketi onu anlamlı kılar.
        #expect(values("Doğrulama kodu: 482913", kind: .code) == ["482913"])
    }

    @Test("Uçuş numarası çıkarılır")
    func extractsFlightNumber() {
        #expect(values("Uçuş: TK 1982", kind: .flightNumber) == ["TK 1982"])
    }

    @Test("Kargo takip numarası çıkarılır")
    func extractsTrackingNumber() {
        #expect(values("Takip No: 1Z999AA10123456784", kind: .trackingNumber)
            == ["1Z999AA10123456784"])
    }

    @Test("Bağlamsız sayı hiçbir varlık üretmez")
    func contextlessNumberProducesNothing() {
        let entities = extractor.extract(from: "482913")
        #expect(entities.allSatisfy { $0.kind != .code && $0.kind != .trackingNumber })
    }

    @Test("E-posta ve bağlantı ayrı türlere gider")
    func separatesEmailFromURL() {
        let entities = extractor.extract(from: "Yaz: destek@ornek.com veya https://ornek.com/yardim")
        #expect(entities.contains { $0.kind == .email && $0.normalizedValue == "destek@ornek.com" })
        #expect(entities.contains { $0.kind == .url })
    }

    @Test("Boş metin boş sonuç verir")
    func emptyTextYieldsNoEntities() {
        #expect(extractor.extract(from: "").isEmpty)
    }
}
