import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import AnalyticsKit

private func catalog(_ experiments: Experiment...) -> ExperimentCatalog {
    ExperimentCatalog(experiments: experiments)
}

/// trafficBasisPoints=10000 + tek varyant → herkes o varyanta atanır (deterministik test).
private func alwaysAssigned(key: String, variantID: String = "v1") -> Experiment {
    Experiment(
        key: key, salt: "s", status: .running, trafficBasisPoints: 10000,
        variants: [ExperimentVariant(id: variantID, weight: 1)]
    )
}

struct ExperimentClientReadTests {
    @Test func atananVaryantiDondurur() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(alwaysAssigned(key: "e")), analytics: analytics, userID: "u1")
        #expect(client.variant(for: "e")?.id == "v1")
    }

    @Test func tanimYoksaNilVeExposureYok() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(), analytics: analytics, userID: "u1")
        #expect(client.variant(for: "yok") == nil)
        #expect(analytics.events.isEmpty)
    }

    @Test func aktifOlmayanDeneyNilVeExposureYok() {
        let analytics = MockAnalytics()
        let draft = Experiment(
            key: "e", salt: "s", status: .draft, trafficBasisPoints: 10000,
            variants: [ExperimentVariant(id: "v1", weight: 1)]
        )
        let client = ExperimentClient(catalog: catalog(draft), analytics: analytics, userID: "u1")
        #expect(client.variant(for: "e") == nil)
        #expect(analytics.events.isEmpty)
    }
}

struct ExperimentExposureTests {
    @Test func ilkOkumadaExposureGonderilir() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(alwaysAssigned(key: "e")), analytics: analytics, userID: "u1")
        _ = client.variant(for: "e")

        #expect(analytics.events.count == 1)
        let event = analytics.events[0]
        #expect(event.name == "ab_exposure")
        #expect(event.parameters["exp_key"] == .string("e"))
        #expect(event.parameters["variant"] == .string("v1"))
        #expect(event.parameters["first_exposure"] == .bool(true))
    }

    @Test func oturumBasinaIdempotent() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(alwaysAssigned(key: "e")), analytics: analytics, userID: "u1")
        for _ in 0 ..< 10 {
            _ = client.variant(for: "e")
        }
        #expect(analytics.eventNames.filter { $0 == "ab_exposure" }.count == 1)
    }

    @Test func farkliDeneylerAyriExposure() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(
            catalog: catalog(alwaysAssigned(key: "e1"), alwaysAssigned(key: "e2")),
            analytics: analytics,
            userID: "u1"
        )
        _ = client.variant(for: "e1")
        _ = client.variant(for: "e2")
        _ = client.variant(for: "e1")
        #expect(analytics.eventNames.filter { $0 == "ab_exposure" }.count == 2)
    }

    @Test func oncekiOturumMaruzKalmaFirstExposureFalse() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(
            catalog: catalog(alwaysAssigned(key: "e")),
            analytics: analytics,
            userID: "u1",
            previouslyExposed: ["e"]
        )
        _ = client.variant(for: "e")
        #expect(analytics.events[0].parameters["first_exposure"] == .bool(false))
    }
}

struct ABVariantsTests {
    @Test func abVariantsMaruzKalinanlariDuzlestirir() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(
            catalog: catalog(alwaysAssigned(key: "b_exp"), alwaysAssigned(key: "a_exp", variantID: "control")),
            analytics: analytics,
            userID: "u1"
        )
        _ = client.variant(for: "b_exp")
        _ = client.variant(for: "a_exp")
        // Anahtara göre sıralı, "key:variant" virgül ayrımlı.
        #expect(client.abVariantsParameter() == "a_exp:control,b_exp:v1")
    }

    @Test func maruzKalmadanBosString() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(alwaysAssigned(key: "e")), analytics: analytics, userID: "u1")
        #expect(client.abVariantsParameter().isEmpty)
    }

    @Test func exposedAnahtarlariPersistIcinAcik() {
        let analytics = MockAnalytics()
        let client = ExperimentClient(catalog: catalog(alwaysAssigned(key: "e")), analytics: analytics, userID: "u1")
        _ = client.variant(for: "e")
        #expect(client.exposedExperimentKeys == ["e"])
    }

    @Test func formatSaltPure() {
        #expect(ABVariants.format(["z": "1", "a": "2"]) == "a:2,z:1")
        #expect(ABVariants.format([:]).isEmpty)
        #expect(ABVariants.parameterKey == "ab_variants")
    }
}
