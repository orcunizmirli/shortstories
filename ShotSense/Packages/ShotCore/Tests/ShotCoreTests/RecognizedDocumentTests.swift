import Testing
@testable import ShotCore

@Suite("RecognizedDocument")
struct RecognizedDocumentTests {
    @Test("Tablo hücreleri boru ile düzleştirilir")
    func tableFlattening() {
        let table = RecognizedDocument.Table(rows: [["Ürün", "Tutar"], ["Kahve", "85,00"]])
        #expect(table.flattened == "Ürün | Tutar\nKahve | 85,00")
    }

    @Test("fullText tüm yapısal parçaları içerir")
    func fullTextIncludesAllParts() {
        let document = RecognizedDocument(
            blocks: [.init(text: "Başlık")],
            tables: [.init(rows: [["a", "b"]])],
            lists: [["madde"]],
            barcodes: [.init(payload: "PNR123", symbology: "qr")]
        )
        let text = document.fullText
        #expect(text.contains("Başlık"))
        #expect(text.contains("a | b"))
        #expect(text.contains("madde"))
        #expect(text.contains("PNR123"))
    }

    @Test("Uzun metin ortadan kırpılır; baş ve son korunur")
    func promptTruncationKeepsHeadAndTail() {
        // Ekran görüntülerinde başlık üstte, toplam/tarih altta olur; ortadan kesmek ikisini de korur.
        let head = String(repeating: "A", count: 3000)
        let tail = String(repeating: "Z", count: 3000)
        let document = RecognizedDocument(blocks: [.init(text: head + tail)])

        let prompt = document.promptRepresentation(maxCharacters: 400)

        #expect(prompt.hasPrefix("A"))
        #expect(prompt.hasSuffix("Z"))
        #expect(prompt.contains("[…]"))
        #expect(prompt.count < 500)
    }

    @Test("Sınır altındaki metin kırpılmaz")
    func shortTextIsNotTruncated() {
        let document = RecognizedDocument(blocks: [.init(text: "kısa metin")])
        #expect(document.promptRepresentation(maxCharacters: 4000) == "kısa metin")
    }

    @Test("Metinsiz belge boş sayılır")
    func emptyDocumentIsEmpty() {
        #expect(RecognizedDocument().isEmpty)
        #expect(RecognizedDocument(blocks: [.init(text: "   ")]).isEmpty)
    }
}
