import Testing
@testable import IntelligenceKit

@Suite("AmountParser")
struct AmountParserTests {
    @Test("Türk ve Amerikan biçimi aynı sayıya çözülür")
    func localeIndependentNormalization() {
        // NumberFormatter tek bir yerel varsayar; ekran görüntüsü arşivi karışıktır.
        #expect(AmountParser.normalize("1.234,56") == 1234.56)
        #expect(AmountParser.normalize("1,234.56") == 1234.56)
    }

    @Test("Üç haneli son grup binlik ayracıdır")
    func threeDigitGroupIsThousands() {
        #expect(AmountParser.normalize("1.234") == 1234)
        #expect(AmountParser.normalize("12.500") == 12500)
    }

    @Test("İki haneli son grup ondalıktır")
    func twoDigitGroupIsDecimal() {
        #expect(AmountParser.normalize("1.23") == 1.23)
        #expect(AmountParser.normalize("249,90") == 249.90)
    }

    @Test("Ayraçsız sayı olduğu gibi çözülür")
    func plainNumber() {
        #expect(AmountParser.normalize("500") == 500)
    }

    @Test("İşaret sayıdan sonra gelebilir")
    func trailingCurrencyMarker() throws {
        let match = try #require(AmountParser.matches(in: "TOPLAM 291,55 TL").first)
        #expect(match.amount == 291.55)
        #expect(match.currencyCode == "TRY")
        #expect(match.rawValue == "291,55")
    }

    @Test("İşaret sayıdan önce gelebilir")
    func leadingCurrencyMarker() throws {
        let match = try #require(AmountParser.matches(in: "Fiyat: ₺1.299,00").first)
        #expect(match.amount == 1299)
        #expect(match.currencyCode == "TRY")
    }

    @Test("Dolar ve euro tanınır")
    func recognizesMajorCurrencies() {
        #expect(AmountParser.matches(in: "$24.99").first?.currencyCode == "USD")
        #expect(AmountParser.matches(in: "49,90 EUR").first?.currencyCode == "EUR")
    }

    @Test("İşaretsiz sayı tutar sayılmaz")
    func bareNumberIsNotAnAmount() {
        // "Sipariş 482913" veya "2.341 yorum" tutar değildir; işaret zorunluluğu bunları eler.
        #expect(AmountParser.matches(in: "Sipariş 482913").isEmpty)
        let mixed = AmountParser.matches(in: "$10 ve 20")
        #expect(mixed.count == 1)
        #expect(mixed[0].amount == 10)
    }

    @Test("Sayısız metinde eşleşme olmaz")
    func noMatchesInPlainText() {
        #expect(AmountParser.matches(in: "merhaba dünya").isEmpty)
    }
}
