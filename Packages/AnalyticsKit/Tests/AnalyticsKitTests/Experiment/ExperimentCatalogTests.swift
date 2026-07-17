import Foundation
import Testing
@testable import AnalyticsKit

struct ExperimentCatalogTests {
    private let json = Data("""
    [
      {
        "key": "exp_unlock_sheet",
        "salt": "s1",
        "status": "running",
        "traffic_basis_points": 10000,
        "variants": [
          { "id": "control", "weight": 1, "payload": { "cta": "coin" } },
          { "id": "v1", "weight": 2, "payload": { "free_eps": 3, "highlight": true, "boost": 1.5 } }
        ]
      },
      {
        "key": "exp_draft",
        "salt": "s2",
        "status": "draft",
        "traffic_basis_points": 5000,
        "variants": [ { "id": "control", "weight": 1 } ]
      }
    ]
    """.utf8)

    @Test func remoteConfigtenYuklenir() throws {
        let catalog = try ExperimentCatalog.decode(from: json)
        #expect(catalog.all.count == 2)
        let unlock = try #require(catalog.experiment(for: "exp_unlock_sheet"))
        #expect(unlock.salt == "s1")
        #expect(unlock.status == .running)
        #expect(unlock.trafficBasisPoints == 10000)
        #expect(unlock.variants.count == 2)
        #expect(unlock.totalWeight == 3)
    }

    @Test func tanimYoksaNil() throws {
        let catalog = try ExperimentCatalog.decode(from: json)
        #expect(catalog.experiment(for: "olmayan_deney") == nil)
    }

    @Test func bosKatalog() {
        let catalog = ExperimentCatalog(experiments: [])
        #expect(catalog.experiment(for: "x") == nil)
        #expect(catalog.all.isEmpty)
    }

    @Test func varyantPayloadTipliOkunur() throws {
        let catalog = try ExperimentCatalog.decode(from: json)
        let unlock = try #require(catalog.experiment(for: "exp_unlock_sheet"))
        let control = try #require(unlock.variant(withID: "control"))
        let v1 = try #require(unlock.variant(withID: "v1"))

        #expect(control.value(for: "cta") == "coin")
        let freeEps: Int? = v1.value(for: "free_eps")
        #expect(freeEps == 3)
        let highlight: Bool? = v1.value(for: "highlight")
        #expect(highlight == true)
        let boost: Double? = v1.value(for: "boost")
        #expect(boost == 1.5)
        // Yanlış tip / eksik anahtar → nil.
        let missing: String? = v1.value(for: "yok")
        #expect(missing == nil)
        let wrongType: String? = v1.value(for: "free_eps")
        #expect(wrongType == nil)
    }

    @Test func statuDurumlariDecodeEdilir() throws {
        let catalog = try ExperimentCatalog.decode(from: json)
        #expect(catalog.experiment(for: "exp_draft")?.status == .draft)
        #expect(catalog.experiment(for: "exp_draft")?.isActive == false)
    }

    @Test func roundTripKodlanabilir() throws {
        let original = Experiment(
            key: "e", salt: "s", status: .running, trafficBasisPoints: 7500,
            variants: [ExperimentVariant(id: "control", weight: 1, payload: ["n": .int(2), "flag": .bool(false)])]
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try ExperimentCatalog.decode(from: data)
        #expect(decoded.experiment(for: "e") == original)
    }
}
