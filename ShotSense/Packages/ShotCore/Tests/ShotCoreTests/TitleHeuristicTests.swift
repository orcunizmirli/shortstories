import Testing
@testable import ShotCore

@Suite("TitleHeuristic")
struct TitleHeuristicTests {
    private func block(
        _ text: String,
        y: Double,
        height: Double = 0.02
    ) -> RecognizedDocument.TextBlock {
        RecognizedDocument.TextBlock(text: text, verticalPosition: y, relativeHeight: height)
    }

    @Test("Statü çubuğu başlık olarak seçilmez")
    func ignoresStatusBar() {
        // Her ekran görüntüsünün tepesinde saat/pil vardır ve punto olarak büyük görünebilir.
        let blocks = [
            block("09:41", y: 0.02, height: 0.03),
            block("Sipariş Özeti", y: 0.12, height: 0.025)
        ]
        #expect(TitleHeuristic.title(from: blocks) == "Sipariş Özeti")
    }

    @Test("Daha büyük punto kazanır")
    func largestTypeWins() {
        let blocks = [
            block("küçük bir alt başlık", y: 0.10, height: 0.015),
            block("Ana Başlık", y: 0.20, height: 0.040)
        ]
        #expect(TitleHeuristic.title(from: blocks) == "Ana Başlık")
    }

    @Test("Eşit puntoda daha bilgi yüklü satır seçilir")
    func longerTextBreaksTie() {
        let blocks = [
            block("Detay", y: 0.10, height: 0.02),
            block("Kargo Takip Numarası", y: 0.15, height: 0.02)
        ]
        #expect(TitleHeuristic.title(from: blocks) == "Kargo Takip Numarası")
    }

    @Test("Arama bandında aday yoksa ilk bloğa düşülür")
    func fallsBackToFirstBlock() {
        let blocks = [block("çok aşağıdaki tek satır", y: 0.80)]
        #expect(TitleHeuristic.title(from: blocks) == "çok aşağıdaki tek satır")
    }

    @Test("Blok yoksa boş döner")
    func emptyInputYieldsEmptyTitle() {
        #expect(TitleHeuristic.title(from: []).isEmpty)
    }

    @Test("Aşırı uzun satır başlık sayılmaz")
    func overlyLongLineIsNotATitle() {
        let paragraph = String(repeating: "uzun paragraf ", count: 20)
        let blocks = [block(paragraph, y: 0.10, height: 0.05), block("Başlık", y: 0.20, height: 0.02)]
        #expect(TitleHeuristic.title(from: blocks) == "Başlık")
    }
}
