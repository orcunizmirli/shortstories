import ShotCore
import Testing
@testable import IntelligenceKit

@Suite("HeuristicAnalyzer")
struct HeuristicAnalyzerTests {
    let analyzer = HeuristicAnalyzer()

    private func document(_ text: String) -> RecognizedDocument {
        let blocks = text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                RecognizedDocument.TextBlock(
                    text: line,
                    verticalPosition: 0.08 + Double(index) * 0.05,
                    relativeHeight: index == 0 ? 0.035 : 0.02
                )
            }
        return RecognizedDocument(blocks: blocks)
    }

    @Test("Boş belge boş analiz üretir, çökmez")
    func emptyDocumentYieldsEmptyAnalysis() {
        let analysis = analyzer.analyzeSynchronously(RecognizedDocument())
        #expect(analysis.category == .other)
        #expect(analysis.entities.isEmpty)
        #expect(analysis.analyzerKind == .heuristic)
    }

    @Test("Analiz her zaman heuristik olarak etiketlenir")
    func analyzerKindIsHeuristic() {
        #expect(analyzer.analyzeSynchronously(document("TOPLAM 10,00 TL")).analyzerKind == .heuristic)
    }

    @Test("Gösterilen tüm varlıklar temellendirilmiştir")
    func allDisplayedEntitiesAreGrounded() {
        let analysis = analyzer.analyzeSynchronously(
            document("IBAN: TR33 0006 1005 1978 6457 8413 26\nTutar: 250,00 TL")
        )
        #expect(!analysis.displayableEntities.isEmpty)
        #expect(analysis.displayableEntities.allSatisfy(\.isGrounded))
    }

    @Test("Özet tek kelimelik satırları atlar")
    func summarySkipsSingleWordLines() {
        // "Tamam", "İptal" gibi düğme etiketleri özet olarak işe yaramaz.
        let summary = HeuristicAnalyzer.summary(
            from: document("Tamam\nİptal\nSiparişiniz yola çıktı ve yarın teslim edilecek")
        )
        #expect(summary.contains("Siparişiniz"))
        #expect(!summary.hasPrefix("Tamam"))
    }

    @Test("Etiketler durak kelime içermez ve deterministiktir")
    func tagsAreCleanAndDeterministic() {
        let text = String(repeating: "kulaklık bluetooth için için ", count: 3)
        let first = HeuristicAnalyzer.tags(from: text, category: .product)
        let second = HeuristicAnalyzer.tags(from: text, category: .product)

        #expect(first == second)
        // Tokenlar katlanmış gelir; durak kelime listesi de katlanmış olmalı ki eşleşsin.
        #expect(!first.contains("icin"))
        #expect(first.contains("kulaklik"))
    }

    @Test("Etiket sayısı sınırı aşmaz")
    func tagsRespectLimit() {
        let text = (0 ..< 20).map { "kelime\($0) kelime\($0)" }.joined(separator: " ")
        #expect(HeuristicAnalyzer.tags(from: text, category: .other).count <= 5)
    }

    @Test("Model etiketi boşsa heuristik etiketlere düşülür")
    func emptyModelTagsFallBack() {
        #expect(
            FoundationModelAnalyzer.normalizedTags([], fallback: ["fis", "market"])
                == ["fis", "market"]
        )
    }

    @Test("Model etiketleri küçültülür, tekilleştirilir ve 5 ile sınırlanır")
    func modelTagsAreNormalized() {
        let tags = FoundationModelAnalyzer.normalizedTags(
            ["Fiş", "fiş", "MARKET", "a", "kdv", "toplam", "ödeme", "nakit"],
            fallback: []
        )
        #expect(tags == ["fiş", "market", "kdv", "toplam", "ödeme"])
    }
}
