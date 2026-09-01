import Foundation
import Testing
@testable import ShotCore

@Suite("ExtractionValidator")
struct ExtractionValidatorTests {
    let validator = ExtractionValidator()

    // MARK: - IBAN

    @Test("Geçerli IBAN'lar mod-97 kontrolünden geçer", arguments: [
        "TR330006100519786457841326",
        "TR33 0006 1005 1978 6457 8413 26",
        "GB82 WEST 1234 5698 7654 32",
        "DE89370400440532013000"
    ])
    func acceptsValidIBANs(_ iban: String) {
        #expect(ExtractionValidator.isValidIBAN(iban))
    }

    @Test("Checksum'ı bozuk IBAN reddedilir")
    func rejectsBrokenChecksum() {
        // Son hane değişti: kullanıcı yanlış hesaba para gönderebilirdi (04 §5).
        #expect(!ExtractionValidator.isValidIBAN("TR330006100519786457841327"))
    }

    @Test("Yapısal olarak IBAN olamayacak değerler reddedilir", arguments: [
        "1234567890123456",        // ülke kodu yok
        "TRAB0006100519786457",    // kontrol haneleri rakam değil
        "TR33",                    // çok kısa
        ""
    ])
    func rejectsMalformedIBANs(_ value: String) {
        #expect(!ExtractionValidator.isValidIBAN(value))
    }

    // MARK: - Grounding

    @Test("Kaynak metinde geçmeyen tutar atılır")
    func hallucinatedAmountIsDropped() {
        let source = "TOPLAM 249,90 TL\nKDV 41,65 TL"
        let entities = [
            ExtractedEntity(kind: .amount, rawValue: "249,90", normalizedValue: "249.90", currencyCode: "TRY"),
            // Model uydurdu: metinde 999,00 diye bir şey yok.
            ExtractedEntity(kind: .amount, rawValue: "999,00", normalizedValue: "999.00", currencyCode: "TRY")
        ]

        let validated = validator.validate(entities, against: source)

        #expect(validated.count == 1)
        #expect(validated[0].normalizedValue == "249.90")
        #expect(validated[0].isGrounded)
    }

    @Test("Tutar ayraç biçimi değişse de rakam dizisiyle eşleşir")
    func amountGroundingIgnoresSeparators() {
        let source = "Ara toplam 1.234,56 EUR"
        let entity = ExtractedEntity(
            kind: .amount, rawValue: "1.234,56", normalizedValue: "1234.56", currencyCode: "EUR"
        )
        #expect(validator.validate([entity], against: source).count == 1)
    }

    @Test("IBAN kaynakta boşluklu yazılmışsa da bulunur")
    func ibanGroundingIgnoresSpacing() {
        let source = "Hesap: TR33 0006 1005 1978 6457 8413 26"
        let entity = ExtractedEntity(
            kind: .iban,
            rawValue: "TR330006100519786457841326",
            normalizedValue: "TR330006100519786457841326"
        )
        #expect(validator.validate([entity], against: source).count == 1)
    }

    @Test("Türkçe büyük/küçük harf farkı eşleşmeyi bozmaz")
    func turkishCaseFoldingWorks() {
        let source = "Satıcı: MİGROS TİCARET A.Ş."
        let entity = ExtractedEntity(kind: .merchant, rawValue: "migros ticaret", normalizedValue: "Migros")
        #expect(validator.validate([entity], against: source).count == 1)
    }

    @Test("Tarih ham hâliyle temellendirilir, normalize hâliyle değil")
    func dateGroundingUsesRawValue() {
        let source = "Uçuş tarihi: 12 Ocak 2026"
        let entity = ExtractedEntity(
            kind: .date, rawValue: "12 Ocak 2026", normalizedValue: "2026-01-12"
        )
        let validated = validator.validate([entity], against: source)
        #expect(validated.count == 1)
        #expect(validated[0].dateValue != nil)
    }

    // MARK: - Yapısal kurallar

    @Test("Desteklenmeyen para birimi kodu reddedilir")
    func rejectsUnknownCurrency() {
        let entity = ExtractedEntity(
            kind: .amount, rawValue: "100", normalizedValue: "100", currencyCode: "USDT"
        )
        #expect(!validator.isStructurallyValid(entity))
    }

    @Test("Ayrıştırılamayan tarih reddedilir")
    func rejectsUnparsableDate() {
        let entity = ExtractedEntity(kind: .date, rawValue: "yarın", normalizedValue: "yarın")
        #expect(!validator.isStructurallyValid(entity))
    }

    @Test("Şemasız URL reddedilir")
    func rejectsSchemelessURL() {
        let entity = ExtractedEntity(kind: .url, rawValue: "example.com", normalizedValue: "example.com")
        #expect(!validator.isStructurallyValid(entity))
    }

    @Test("Geçersiz e-posta reddedilir", arguments: ["ad@", "@site.com", "ad@site", "ad site@x.com"])
    func rejectsInvalidEmails(_ value: String) {
        #expect(!ExtractionValidator.isPlausibleEmail(value))
    }

    @Test("Aynı tür + aynı değer tekrar eden varlıklar teke indirilir")
    func deduplicatesRepeatedEntities() {
        let source = "TOPLAM 50,00 TL toplam 50,00 TL"
        let entities = [
            ExtractedEntity(kind: .amount, rawValue: "50,00", normalizedValue: "50.00", currencyCode: "TRY"),
            ExtractedEntity(kind: .amount, rawValue: "50,00", normalizedValue: "50.00", currencyCode: "TRY")
        ]
        #expect(validator.validate(entities, against: source).count == 1)
    }
}
