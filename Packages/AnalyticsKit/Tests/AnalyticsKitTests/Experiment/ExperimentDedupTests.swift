import Foundation
import Testing
@testable import AnalyticsKit

/// Audit LOW (spec-config savunması): aynı id'li yinelenen variant → hash bucketing kümülatif yürüyüşte
/// SONRAKİ duplike'yi seçebilir ama `variant(withID:)` `first`'i döner → aynı raporlanan variant id
/// FARKLI payload'a eşlenir (tutarsız deney davranışı). Yapımda id-dedup (İLK'i tut, sıra korunur).
struct ExperimentVariantDedupTests {
    @Test func duplicateVariantIDDedupedKeepingFirstOnInit() {
        let experiment = Experiment(
            key: "e", salt: "s", status: .running, trafficBasisPoints: 10000,
            variants: [
                ExperimentVariant(id: "v1", weight: 1, payload: ["style": .string("a")]),
                ExperimentVariant(id: "v1", weight: 1, payload: ["style": .string("b")]), // duplike id
                ExperimentVariant(id: "v2", weight: 1)
            ]
        )
        #expect(experiment.variants.map(\.id) == ["v1", "v2"]) // v1 tek (ilk), v2
        let style: String? = experiment.variant(withID: "v1")?.value(for: "style")
        #expect(style == "a") // İLK v1'in payload'ı (variant(withID:) ile bucketing tutarlı)
    }

    @Test func duplicateVariantIDDedupedOnDecode() throws {
        // Remote config ANA yol (synthesized decode designated init'i ATLAR) → decode da dedup etmeli.
        let json = Data(#"""
        {"key":"e","salt":"s","status":"running","traffic_basis_points":10000,
         "variants":[{"id":"v1","weight":1},{"id":"v1","weight":2},{"id":"v2","weight":1}]}
        """#.utf8)
        let experiment = try JSONDecoder().decode(Experiment.self, from: json)
        #expect(experiment.variants.map(\.id) == ["v1", "v2"])
    }
}
