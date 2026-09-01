import ShotCore
import Testing
@testable import IntelligenceKit

@Suite("CategoryClassifier")
struct CategoryClassifierTests {
    let classifier = CategoryClassifier()

    @Test("Zayıf kanıt sınıflandırmaya yetmez")
    func weakEvidenceFallsBackToOther() {
        // Tek bir düşük ağırlıklı kelime kategori belirlemek için yeterli değildir:
        // yanlış sınıflandırmak, sınıflandırmamaktan kötüdür (kullanıcı yanlış klasörde arar).
        let (category, confidence) = classifier.classify("Toplam")
        #expect(category == .other)
        #expect(confidence == 0)
    }

    @Test("Boş metin other döner")
    func emptyTextIsOther() {
        #expect(classifier.classify("").category == .other)
    }

    @Test("Güçlü kanıt yüksek güven üretir")
    func strongEvidenceYieldsHighConfidence() {
        let (category, confidence) = classifier.classify(
            "FİŞ NO 12\nARA TOPLAM 100,00 TL\nKDV 20,00 TL\nTOPLAM 120,00 TL\nÖDENDİ"
        )
        #expect(category == .receipt)
        #expect(confidence > 0.6)
    }

    @Test("Güven 0.95'i aşmaz")
    func confidenceIsCapped() {
        // Heuristik yol asla "kesin" diyemez; LLM sonucunun onu ezebilmesi için tavan bırakılır.
        let text = String(repeating: "kdv fiş fatura makbuz ara toplam ödendi ", count: 20)
        #expect(classifier.classify(text).confidence <= 0.95)
    }

    @Test("Türkçe ve İngilizce aynı kategoriye gider")
    func bilingualClassification() {
        #expect(classifier.classify("Malzemeler\nHazırlanışı\nporsiyon").category == .recipe)
        #expect(classifier.classify("Ingredients\nPreheat oven\nservings").category == .recipe)
    }
}
