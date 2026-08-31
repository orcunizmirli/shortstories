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

    @Test func formatYuzKarakterSinirinaKirpilirTamAtamalarla() {
        // Audit LOW: Firebase/GA4 string-parametre sınırı 100 karakter — aşan sessizce DÜŞÜRÜLÜR.
        // Çok deney biriktikçe sınırı aşmasın: yalnız TAM sığan atamalar (yarım variant yok) dahil edilir.
        let many = Dictionary(uniqueKeysWithValues: (0 ..< 50).map { ("exp\($0)", "variant\($0)") })
        let out = ABVariants.format(many)
        #expect(out.count <= 100) // sınıra kırpıldı
        #expect(!out.hasSuffix(",")) // son giriş tam (virgülle bitmez)
        #expect(!out.hasSuffix(":")) // yarım "key:" yok
        // Sınır içindeyse hiçbir şey kırpılmaz.
        #expect(ABVariants.format(["a": "v1", "b": "control"]) == "a:v1,b:control")
    }

    @Test func formatUzunGirdiyiAtlarSonrakiSiganiKorur() {
        // Audit LOW: 100 karakteri aşan İLK girdide 'break' ediliyordu → sıralamada SONRAKİ sığabilecek
        // (kısa) atamalar da atlanıyordu (bir deney ab_variants'tan eksik). Fix: aşan atlanır (continue),
        // sığan sonrakiler korunur.
        let assignments = [
            "a": String(repeating: "x", count: 90), // "a:" + 90 = 92 (sığar)
            "m": String(repeating: "y", count: 20), // ",m:" + 20 = 23 → 115 (taşar)
            "z": "v" // ",z:v" = 4 → 96 (m atlanınca sığar)
        ]
        let out = ABVariants.format(assignments)
        #expect(out.contains("z:v")) // sonraki sığan korundu (break'te düşerdi)
        #expect(!out.contains("m:")) // taşan atlandı
        #expect(out.count <= 100)
    }

    @Test func formatDelimiterIcerenGirdiyiAtlarDigerleriBozulmaz() {
        // #3 (LOW hardening, AnalyticsKit hunt): key/value `:` ya da `,` içerirse düzleştirilmiş string
        // ambiguous olur (backend yanlış pair'lere böler). Fix: o girdiyi ATLA → diğer deneylerin pair'leri
        // bozulmaz (ambiguous pair yaymaktan iyidir).
        let out = ABVariants.format([
            "a": "v1", // temiz → dahil
            "bad": "x,y", // value virgül → atla
            "b:z": "control", // key iki-nokta → atla
            "c": "ok" // temiz → dahil
        ])
        #expect(out == "a:v1,c:ok") // yalnız temiz pair'ler, sıralı; bozuklar atlandı
    }
}
