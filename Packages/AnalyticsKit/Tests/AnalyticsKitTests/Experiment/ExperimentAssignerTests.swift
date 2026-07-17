import Testing
@testable import AnalyticsKit

private func makeExperiment(
    key: String = "exp_test",
    salt: String = "salt_test",
    status: ExperimentStatus = .running,
    trafficBasisPoints: Int = 10000,
    variants: [ExperimentVariant] = [
        ExperimentVariant(id: "control", weight: 1),
        ExperimentVariant(id: "v1", weight: 1)
    ]
) -> Experiment {
    Experiment(key: key, salt: salt, status: status, trafficBasisPoints: trafficBasisPoints, variants: variants)
}

struct ExperimentBucketTests {
    @Test func bucketAralikta() {
        for index in 0 ..< 500 {
            let b = DeterministicExperimentAssigner.bucket(userID: "user-\(index)", experimentKey: "e", salt: "s")
            #expect(b >= 0 && b < 10000)
        }
    }

    @Test func bucketDeterministik() {
        let a = DeterministicExperimentAssigner.bucket(userID: "u1", experimentKey: "e", salt: "s")
        let b = DeterministicExperimentAssigner.bucket(userID: "u1", experimentKey: "e", salt: "s")
        #expect(a == b)
    }

    @Test func saltDegisimiBucketiDegistirir() {
        // Farklı salt → deneyler arası korelasyonsuz atama (§7.2). Aynı girdi için salt'lar
        // hepsi aynı bucket'a düşemez.
        let buckets = ["s1", "s2", "s3", "s4", "s5"].map {
            DeterministicExperimentAssigner.bucket(userID: "u", experimentKey: "e", salt: $0)
        }
        #expect(Set(buckets).count > 1)
    }

    @Test func farkliKullaniciFarkliBucket() {
        let buckets = (0 ..< 8).map {
            DeterministicExperimentAssigner.bucket(userID: "user-\($0)", experimentKey: "e", salt: "s")
        }
        #expect(Set(buckets).count > 1)
    }
}

struct ExperimentAssignmentTests {
    private let assigner = DeterministicExperimentAssigner()

    @Test func yapiskanAyniVaryant() {
        // Aynı kullanıcı + deney her çağrıda aynı varyant (stickiness, §7.2).
        let experiment = makeExperiment()
        let first = assigner.assignment(for: experiment, userID: "kullanici-42")
        for _ in 0 ..< 20 {
            #expect(assigner.assignment(for: experiment, userID: "kullanici-42") == first)
        }
        #expect(first != nil)
    }

    @Test func aktifDegilseVaryantsiz() {
        for status in [ExperimentStatus.draft, .paused, .completed] {
            let experiment = makeExperiment(status: status)
            #expect(assigner.assignment(for: experiment, userID: "u1") == nil)
        }
    }

    @Test func sifirTrafikHicKimseAtanmaz() {
        let experiment = makeExperiment(trafficBasisPoints: 0)
        for index in 0 ..< 200 {
            #expect(assigner.assignment(for: experiment, userID: "user-\(index)") == nil)
        }
    }

    @Test func tamTrafikHerkesAtanir() {
        let experiment = makeExperiment(trafficBasisPoints: 10000)
        for index in 0 ..< 200 {
            #expect(assigner.assignment(for: experiment, userID: "user-\(index)") != nil)
        }
    }

    @Test func agirlikDagilimiDengeli() {
        // 50/50 ağırlık → büyük örneklemde ~yarı yarıya. Deterministik girdiler → stabil.
        let experiment = makeExperiment(trafficBasisPoints: 10000)
        var counts: [String: Int] = [:]
        let sampleCount = 4000
        for index in 0 ..< sampleCount {
            if let variant = assigner.assignment(for: experiment, userID: "user-\(index)") {
                counts[variant.id, default: 0] += 1
            }
        }
        let controlShare = Double(counts["control", default: 0]) / Double(sampleCount)
        let v1Share = Double(counts["v1", default: 0]) / Double(sampleCount)
        #expect(controlShare > 0.45 && controlShare < 0.55)
        #expect(v1Share > 0.45 && v1Share < 0.55)
    }

    @Test func kismiTrafikYaklasikYuzde() {
        // %30 trafik → dahil edilenler ~%30 (deterministik, stabil).
        let experiment = makeExperiment(trafficBasisPoints: 3000)
        var included = 0
        let sampleCount = 4000
        for index in 0 ..< sampleCount where assigner.assignment(for: experiment, userID: "user-\(index)") != nil {
            included += 1
        }
        let share = Double(included) / Double(sampleCount)
        #expect(share > 0.26 && share < 0.34)
    }

    @Test func agirlikliDagilimOranli() {
        // 3:1 ağırlık → v_major ~%75, v_minor ~%25.
        let experiment = makeExperiment(
            variants: [ExperimentVariant(id: "major", weight: 3), ExperimentVariant(id: "minor", weight: 1)]
        )
        var counts: [String: Int] = [:]
        let sampleCount = 4000
        for index in 0 ..< sampleCount {
            if let variant = assigner.assignment(for: experiment, userID: "user-\(index)") {
                counts[variant.id, default: 0] += 1
            }
        }
        let majorShare = Double(counts["major", default: 0]) / Double(sampleCount)
        #expect(majorShare > 0.70 && majorShare < 0.80)
    }

    @Test func agirliksizVaryantYok() {
        let experiment = makeExperiment(
            variants: [ExperimentVariant(id: "a", weight: 0), ExperimentVariant(id: "b", weight: 0)]
        )
        #expect(assigner.assignment(for: experiment, userID: "u1") == nil)
    }

    @Test func bosVaryantYok() {
        let experiment = makeExperiment(variants: [])
        #expect(assigner.assignment(for: experiment, userID: "u1") == nil)
    }
}

struct ExperimentServerOverrideTests {
    @Test func serverAtamasiHashiOverrideEder() {
        // Server açık atama verirse hash yerine o kullanılır (server-otoriter).
        let experiment = makeExperiment()
        let forcing = DeterministicExperimentAssigner(serverAssignments: [experiment.key: "v1"])
        for index in 0 ..< 100 {
            #expect(forcing.assignment(for: experiment, userID: "user-\(index)")?.id == "v1")
        }
    }

    @Test func gecersizServerAtamasiHasheDuser() {
        // Server geçersiz bir varyant id verirse (tanımda yok) deterministik hash'e düşülür.
        let experiment = makeExperiment()
        let assigner = DeterministicExperimentAssigner(serverAssignments: [experiment.key: "olmayan"])
        let hashOnly = DeterministicExperimentAssigner()
        #expect(assigner.assignment(for: experiment, userID: "u1") == hashOnly.assignment(for: experiment, userID: "u1"))
        #expect(assigner.assignment(for: experiment, userID: "u1") != nil)
    }

    @Test func serverAtamasiAktifOlmayaniAtlar() {
        // Deney aktif değilse server override'ı bile varyant üretmez (§7.4).
        let experiment = makeExperiment(status: .draft)
        let assigner = DeterministicExperimentAssigner(serverAssignments: [experiment.key: "v1"])
        #expect(assigner.assignment(for: experiment, userID: "u1") == nil)
    }
}
