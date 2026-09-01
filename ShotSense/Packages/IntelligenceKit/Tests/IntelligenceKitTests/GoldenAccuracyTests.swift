import ShotCore
import Testing
@testable import IntelligenceKit

@Suite("Altın küme doğruluğu")
struct GoldenAccuracyTests {
    private let analyzer = HeuristicAnalyzer()

    /// CI kapısı: heuristik yol LLM'siz cihazlarda TEK yoldur (KANON §5), bu yüzden
    /// doğruluğu sözleşmedir. Eşiğin altına düşen bir sözlük değişikliği build'i kırar.
    @Test("Kategori doğruluğu %70 eşiğinin üstünde")
    func categoryAccuracyMeetsThreshold() {
        let correct = GoldenCorpus.entries.count { entry in
            analyzer.analyzeSynchronously(GoldenCorpus.document(for: entry)).category
                == entry.expectedCategory
        }
        let accuracy = Double(correct) / Double(GoldenCorpus.entries.count)

        #expect(
            accuracy >= 0.70,
            "Kategori doğruluğu \(Int(accuracy * 100))% — eşik %70 (04 §7)"
        )
    }

    @Test("Beklenen varlık türleri çıkarılır", arguments: GoldenCorpus.entries.filter {
        !$0.expectedEntityKinds.isEmpty
    })
    func expectedEntitiesAreExtracted(_ entry: GoldenCorpus.Entry) {
        let analysis = analyzer.analyzeSynchronously(GoldenCorpus.document(for: entry))
        let found = Set(analysis.displayableEntities.map(\.kind))

        for kind in entry.expectedEntityKinds {
            #expect(found.contains(kind), "\(entry.name): \(kind.rawValue) çıkarılamadı")
        }
    }

    @Test("Çıkarılan her varlık kaynak metinde temellendirilmiştir", arguments: GoldenCorpus.entries)
    func everyDisplayedEntityIsGrounded(_ entry: GoldenCorpus.Entry) {
        // KANON §6: gösterilen hiçbir değer uydurulmuş olamaz.
        let analysis = analyzer.analyzeSynchronously(GoldenCorpus.document(for: entry))
        #expect(analysis.displayableEntities.allSatisfy(\.isGrounded))
    }
}

extension GoldenCorpus.Entry: CustomTestStringConvertible {
    var testDescription: String { name }
}
