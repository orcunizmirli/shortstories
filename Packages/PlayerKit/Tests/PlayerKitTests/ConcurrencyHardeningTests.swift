import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// MARK: - Yarış harness'ı

private final class RaceBackendBox: @unchecked Sendable {
    private let lock = NSLock()
    private var created: [FakeVideoPlaying] = []

    var backends: [FakeVideoPlaying] {
        lock.withLock { created }
    }

    var factory: @Sendable () -> any VideoPlaying {
        {
            let backend = FakeVideoPlaying()
            self.lock.withLock { self.created.append(backend) }
            return backend
        }
    }
}

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int {
        lock.withLock { value }
    }

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private func makePool(
    backendBox: RaceBackendBox,
    playback: any PlaybackServicing
) -> PlayerPool {
    PlayerPool(
        size: 3,
        backendFactory: backendBox.factory,
        playback: playback,
        entitlements: FakeEntitlements(),
        network: FakeNetworkProvider(.wifi),
        preferences: FakePreferences(),
        logger: MockLogger()
    )
}

private func loadCount(of backend: FakeVideoPlaying) -> Int {
    backend.calls.count { call in
        if case .load = call {
            return true
        }
        return false
    }
}

/// Suspension noktaları arası korkuluk testleri: her test, sahte backend/authorizer'a
/// eklenmiş kontrollü askı noktalarıyla (CheckedContinuation kapıları) yarışı
/// DETERMİNİSTİK kurar — zamanlayıcı/sleep tabanlı kumar yoktur.
struct PlayerPoolConcurrencyTests {
    @Test func esZamanliFarkliBolumAcquirelariAyniSlotuEzmez() async throws {
        // Bulgu 1/7 (claim-önce-await): warm(e5) authorize'da askıdayken activate(e6)
        // girer; rezervasyon senkron yazılmazsa ikisi AYNI slotu seçip birbirini ezer.
        let box = RaceBackendBox()
        let service = GatedPlaybackService()
        let pool = makePool(backendBox: box, playback: service)
        let warmEpisode = Fixture.episode(id: "e5")
        let activeEpisode = Fixture.episode(id: "e6")

        let warmTask = Task { await pool.prepareNext(warmEpisode, atFeedIndex: 5) }
        await service.gate.awaitEntered("e5") // warm authorize suspension'ında

        let activateTask = Task { try await pool.activate(activeEpisode, atFeedIndex: 6) }
        await service.gate.awaitEntered("e6") // activate de authorize'a ulaştı

        service.gate.open("e5")
        service.gate.open("e6")
        let handle = try await activateTask.value
        await warmTask.value

        #expect(handle.episodeID == activeEpisode.id)
        let ids = await pool.snapshotEpisodeIDs()
        #expect(ids.contains(warmEpisode.id)) // e5 kendi slotunda
        #expect(ids.contains(activeEpisode.id)) // e6 FARKLI slotta
        // Hiçbir backend'e iki farklı bölüm yüklenmedi: aktif oynatma ezilmedi.
        for backend in box.backends {
            let loadedURLs = Set(backend.calls.compactMap { call -> String? in
                if case let .load(url, _) = call {
                    return url.absoluteString
                }
                return nil
            })
            #expect(loadedURLs.count <= 1)
        }
    }

    @Test func ayniBolumIcinEsZamanliAcquireTekYuklemeYapar() async throws {
        // Bulgu 7 (dedup korkuluğu): warm(e7) claim'i authorize'da askıdayken
        // activate(e7) gelir — mükerrer acquire dedup'a takılmalı, çift prepare OLMAMALI.
        let box = RaceBackendBox()
        let service = GatedPlaybackService()
        let pool = makePool(backendBox: box, playback: service)
        let episode = Fixture.episode(id: "e7")
        let acquireGate = TestGate()
        let entryCounter = CounterBox()
        await pool.setAcquireObserver { episodeID in
            acquireGate.signal("acquire:\(episodeID.rawValue)#\(entryCounter.next())")
        }

        let warmTask = Task { await pool.prepareNext(episode, atFeedIndex: 7) }
        await service.gate.awaitEntered("e7") // warm authorize suspension'ında

        let activateTask = Task { try await pool.activate(episode, atFeedIndex: 7) }
        // activate acquire'a girdi; havuz aktörü onu senkron biçimde kendi askı
        // noktasına taşıyacak — kapı ancak bundan sonra açılır (deterministik pencere).
        await acquireGate.awaitEntered("acquire:e7#2")
        service.gate.open("e7")

        let handle = try await activateTask.value
        await warmTask.value

        #expect(handle.episodeID == episode.id)
        #expect(service.authorizeCallCount == 1) // tek uçuş (coalesced)
        let ids = await pool.snapshotEpisodeIDs()
        #expect(ids.count { $0 == episode.id } == 1) // bölüm tek slotta
        let totalLoads = box.backends.map(loadCount(of:)).reduce(0, +)
        #expect(totalLoads == 1) // çift prepare yok
        let roles = await pool.snapshotRoles()
        #expect(roles.contains(.active)) // aktivasyon rolü kazandı
    }

    @Test func failedWarmSlotAktivasyondaYenidenHazirlanir() async throws {
        // Bulgu 2 (slot sağlığı): warm slot kurtarılamaz hatayla .failed'a düşer;
        // auth hâlâ taze olsa da warm-hit aktivasyonu YENİDEN prepare etmelidir.
        let box = RaceBackendBox()
        let service = PlaybackServicingSpy()
        let pool = makePool(backendBox: box, playback: service)
        let episode = Fixture.episode(id: "e2")
        await pool.prepareNext(episode, atFeedIndex: 1)
        let backend = box.backends[0]
        #expect(loadCount(of: backend) == 1)

        backend.emit(.didFail(.network(.offline))) // kurtarma dışı hata → .failed
        let failureSurfaced = await eventually {
            await pool.snapshotEngineStates().contains(.failed(.network(.offline)))
        }
        #expect(failureSurfaced)

        let handle = try await pool.activate(episode, atFeedIndex: 1)

        #expect(loadCount(of: backend) == 2) // ölü engine yeniden hazırlandı
        backend.emit(.firstFrameReady)
        let playing = await eventually { await handle.currentState() == .playing }
        #expect(playing)
    }

    @Test func drainSonrasiUcustakiActivateTemizCikar() async {
        // Bulgu 10 (epoch drain): activate authorize'da askıdayken drain gelirse
        // dönüşte slot yazılmaz, oynatma başlatılmaz; çağrı iptalle temiz çıkar.
        let box = RaceBackendBox()
        let service = GatedPlaybackService()
        let pool = makePool(backendBox: box, playback: service)
        let episode = Fixture.episode(id: "e1")

        let activateTask = Task { try await pool.activate(episode, atFeedIndex: 0) }
        await service.gate.awaitEntered("e1")
        await pool.drain() // kullanıcı feed'den çıktı
        service.gate.open("e1")

        let result = await activateTask.result
        var cancelledCleanly = false
        if case let .failure(error) = result {
            cancelledCleanly = error is CancellationError
        }
        #expect(cancelledCleanly) // yazmadan/başlatmadan iptal
        #expect(await pool.snapshotEpisodeIDs().allSatisfy { $0 == nil })
        let anyLoad = box.backends.contains { loadCount(of: $0) > 0 }
        #expect(!anyLoad) // hayalet oynatma yok (arka planda ses çalmaz)
    }
}

/// PlaybackEngine jenerasyon korkuluğu testleri: bayat runtime olayları (buffer'da
/// bekleyen ya da KVO→Task köprüsünde geciken) güncel yüklemeye UYGULANMAZ.
struct PlaybackEngineGenerationTests {
    private let urlA = URL(string: "https://cdn.test/a/master.m3u8")!
    private let urlB = URL(string: "https://cdn.test/b/master.m3u8")!
    private let urlFresh = URL(string: "https://cdn.test/fresh/master.m3u8")!

    @Test func bayatIlkKareSinyaliYeniYuklemeyeUygulanmaz() async {
        // Bulgu 3: önceki item'ın geciken firstFrame sinyali, planlandığı yükleme
        // jenerasyonunu taşır; yeni item hâlâ yüklenirken işleme ALINMAZ.
        let backend = FakeVideoPlaying()
        let engine = PlaybackEngine(backend: backend)
        await engine.prepare(episodeID: EpisodeID("a"), url: urlA, bufferPolicy: .active)
        let staleGeneration = backend.lastLoadGeneration

        await engine.prepare(episodeID: EpisodeID("b"), url: urlB, bufferPolicy: .active)
        backend.emit(.firstFrameReady, generation: staleGeneration)
        await settle(engine)

        #expect(await engine.currentState() == .loading) // bayat sinyal düştü

        backend.emit(.firstFrameReady) // gerçek ilk kare (güncel jenerasyon)
        #expect(await awaitState(.readyAtFirstFrame, on: engine)) // yutulmadı
    }

    @Test func bayatDidFailYeniBolumdeKurtarmaTetiklemez() async {
        // Bulgu 4: önceki item'ın buffer'da bekleyen didFail'i prepare sonrası
        // tüketilirse yeni bölüm için kurtarma (pendingPlay=true) BAŞLATMAMALI.
        let backend = FakeVideoPlaying()
        let freshCalls = CounterBox()
        let freshURL = urlFresh
        let engine = PlaybackEngine(backend: backend, freshURLProvider: { _ in
            _ = freshCalls.next()
            return freshURL
        })
        await engine.prepare(episodeID: EpisodeID("e3"), url: urlA, bufferPolicy: .idle)
        let staleGeneration = backend.lastLoadGeneration

        await engine.prepare(episodeID: EpisodeID("e4"), url: urlB, bufferPolicy: .idle)
        backend.emit(.didFail(.playback(.signedURLExpired)), generation: staleGeneration)
        await settle(engine)

        #expect(freshCalls.current == 0) // bayat hata kurtarma tetiklemedi
        #expect(loadCount(of: backend) == 2) // kurtarma yüklemesi yok

        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        #expect(!backend.calls.contains(.playImmediately(1.0))) // pendingPlay bulaşmadı
    }

    @Test func resetSonrasiKurtarmaIptalEdilir() async {
        // Bulgu 8: kurtarma freshURL'de askıdayken reset (recycle/drain) gelirse
        // dönüşte boşaltılmış slot diriltilMEZ: yükleme yok, hayalet ses yok.
        let backend = FakeVideoPlaying()
        let gate = TestGate()
        let freshURL = urlFresh
        let engine = PlaybackEngine(backend: backend, freshURLProvider: { _ in
            await gate.pass("fresh")
            return freshURL
        })
        await engine.prepare(episodeID: EpisodeID("e1"), url: urlA, bufferPolicy: .idle)

        backend.emit(.didFail(.playback(.signedURLExpired)))
        await gate.awaitEntered("fresh") // kurtarma taze URL bekliyor
        await engine.reset() // araya recycle/drain girdi
        gate.open("fresh")
        await settle(engine)

        #expect(loadCount(of: backend) == 1) // boşaltılmış slota yükleme YOK
        #expect(await engine.currentState() == .idle)
        #expect(!backend.calls.contains(.playImmediately(1.0)))
    }

    @Test func warmSlotKurtarmasiKendiligindenOynamaz() async {
        // Bulgu 9 (rol farkındalığı): warm (paused, .idle buffer) slotun kurtarması
        // pendingPlay=false + .idle ile yeniden yükler; ilk karede oynatma BAŞLAMAZ.
        let backend = FakeVideoPlaying()
        let freshURL = urlFresh
        let engine = PlaybackEngine(backend: backend, freshURLProvider: { _ in freshURL })
        await engine.prepare(episodeID: EpisodeID("e6"), url: urlA, bufferPolicy: .idle)
        backend.setPosition(10)

        backend.emit(.didFail(.playback(.signedURLExpired)))

        let reloadedAsIdle = await eventually { backend.calls.contains(.load(freshURL, .idle)) }
        #expect(reloadedAsIdle) // .active DEĞİL, .idle ile yeniden yüklendi
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        #expect(!backend.calls.contains(.playImmediately(1.0))) // gizli ses yok
    }
}

/// PrefetchController görev kimliği + PlayerMetricsCollector hijyen testleri.
struct PrefetchIdentityAndMetricsTests {
    @Test func iptalEdilipYenilenenWarmTaskYenisiniSilmez() async {
        // Bulgu 5: iptal edilen A görevi geç tamamlanınca, aynı bölüm için kayıtlı
        // YENİ B görevini defterden düşürmemeli (anahtar varlığı değil görev kimliği).
        let warmer = GatedWarmer()
        let controller = PrefetchController(
            warmer: warmer,
            network: FakeNetworkProvider(.wifi),
            preferences: FakePreferences(),
            poolSize: 3
        )
        let episodes = Fixture.episodes(count: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let e6 = EpisodeID("e6")

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward, at: t0)
        await warmer.gate.awaitEntered("e6#1") // A görevi warm içinde askıda
        let taskA = await controller.pendingTask(for: e6)
        #expect(taskA != nil)

        // Geri yön: e6 hedef dışı → A iptal edilir ama gövdesi hâlâ kapıda.
        await controller.windowChanged(
            activeIndex: 5, episodes: episodes, direction: .backward, at: t0.addingTimeInterval(1)
        )
        // Tekrar ileri: e6 için YENİ B görevi kaydedilir.
        await controller.windowChanged(
            activeIndex: 5, episodes: episodes, direction: .forward, at: t0.addingTimeInterval(2)
        )
        await warmer.gate.awaitEntered("e6#2")
        let taskB = await controller.pendingTask(for: e6)
        #expect(taskB != nil)
        #expect(taskA != taskB)

        warmer.gate.open("e6#1") // A geç tamamlanır (iptal edilmiş olarak)
        if let taskA {
            await taskA.value // tamamlanma işleyicisi koştu
        }

        let trackedAfterLateCompletion = await controller.pendingTask(for: e6)
        #expect(trackedAfterLateCompletion == taskB) // B defterde KALDI

        warmer.gate.open("e6#2")
        warmer.gate.open("e4#1")
        await controller.awaitPendingWarmups()
    }

    @Test func basarisizNiyetinIlkKaresiOlcumUretmez() async {
        // Bulgu 6: failure, bekleyen TTFF niyetini temizler — sonraki başarılı
        // başlangıç bayat t0 ile video_start üretmez.
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e8")
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        await collector.recordPlaybackIntent(for: episode, startType: .tap, at: t0)
        await collector.recordPlaybackFailure(for: episode.id)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.3))

        #expect(!analytics.eventNames.contains("video_start"))
    }

    @Test func bayatNiyetTTFFOlcumuneKatilmaz() async {
        // Bulgu 6 (expiry): tazelik penceresini aşan niyet, dakikalar sonraki
        // başarılı başlangıçta saçma ttff_ms üretmek yerine SESSİZCE düşer.
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e8")
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        await collector.recordPlaybackIntent(for: episode, startType: .tap, at: t0)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(1200)) // 20 dk sonra

        #expect(!analytics.eventNames.contains("video_start"))
    }

    @Test func bekleyenNiyetlerTavaniAsmaz() async {
        // Bulgu 6 (üst sınır): terk edilen başlangıçlar sınırsız birikmez; tavan
        // aşıldığında EN ESKİ niyet düşer, yeniler ölçülmeye devam eder.
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let overflow = PlayerMetricsCollector.maxPendingIntents + 1
        for index in 0 ..< overflow {
            await collector.recordPlaybackIntent(
                for: Fixture.episode(id: "cap\(index)"),
                startType: .tap,
                at: t0.addingTimeInterval(Double(index))
            )
        }
        let later = t0.addingTimeInterval(Double(overflow))

        await collector.recordFirstFrame(for: Fixture.episode(id: "cap0"), at: later)
        #expect(!analytics.eventNames.contains("video_start")) // en eski düştü

        await collector.recordFirstFrame(for: Fixture.episode(id: "cap\(overflow - 1)"), at: later)
        #expect(analytics.eventNames.contains("video_start")) // yeniler ölçülüyor
    }
}
