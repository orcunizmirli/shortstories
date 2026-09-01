import Testing
@testable import OCRKit

@Suite("OCRConfiguration")
struct OCRConfigurationTests {
    @Test("Varsayılan yapılandırma Türkçe ve İngilizceyi bu sırayla ister")
    func defaultLanguages() {
        // Sıra önemlidir: Vision ilk dili öncelikli sözlük olarak kullanır.
        #expect(OCRConfiguration.default.languages == ["tr-TR", "en-US"])
    }

    @Test("Ekran görüntüleri için güven eşiği yüksek tutulur")
    func confidenceThresholdIsStrict() {
        // Dijital kökenli, yüksek kontrastlı görüntülerde düşük güvenli satır neredeyse her
        // zaman arayüz gürültüsüdür (saat, pil, ikon altyazısı).
        #expect(OCRConfiguration.default.minimumConfidence >= 0.4)
    }

    @Test("Boş yapı sonucu tablo ve liste içermez")
    func emptyStructureIsEmpty() {
        #expect(DocumentStructure.empty.tables.isEmpty)
        #expect(DocumentStructure.empty.lists.isEmpty)
    }
}
