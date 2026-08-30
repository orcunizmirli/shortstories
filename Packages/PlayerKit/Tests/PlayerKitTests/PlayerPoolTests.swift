import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

/// PlayerPool actor testleri (04 §3, SS-040): acquire/reuse, pencere geri dönüşümü,
/// buffer politikası rolleri (04 §4.1), kilit sınırı (04 §9) ve drain davranışı.
/// Backend'ler sahtedir; havuz mantığı gerçek medya olmadan doğrulanır.
struct PlayerPoolTests {
    @Test func havuzBoyutuKadarBackendYaratilir() async {
        let harness = makePool(size: 3)
        let (pool, box) = (harness.pool, harness.box)
        _ = await pool.slotCount // aktör kurulumunu bekle
        #expect(box.backends.count == 3)
    }

    @Test func activateSerbestBolumuYuklerVeOynatir() async throws {
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")

        let handle = try await pool.activate(episode, atFeedIndex: 0)

        #expect(handle.episodeID == episode.id)
        let backend = box.backends[0]
        #expect(backend.calls.contains { call in
            if case let .load(_, policy) = call {
                return policy == .active
            }
            return false
        })
        // İlk kare gelince oynatma niyeti uygulanır (playImmediately — 04 §4.2).
        backend.emit(.firstFrameReady)
        #expect(await eventually { backend.calls.contains(.playImmediately(1.0)) })
    }

    @Test func warmBolumIdleBufferIleHazirlanir() async {
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e2")

        await pool.prepareNext(episode, atFeedIndex: 1)

        let loaded = box.backends.contains { backend in
            backend.calls.contains { call in
                if case let .load(_, policy) = call {
                    return policy == .idle
                }
                return false
            }
        }
        #expect(loaded) // idle player 1 sn buffer (04 §4.1)
        let played = box.backends.contains { $0.calls.contains(.playImmediately(1.0)) }
        #expect(!played)
    }

    @Test func warmAuthorizeHataSinifinaGoreRetryKarariDoner() async {
        // KALICI içerik hatası (4xx, isRetryable=false) → true (completedWarmups'a girer, boşa authorize önlenir).
        let permanent = makePool()
        permanent.service.setFailure(.network(.server(status: 404)))
        #expect(await permanent.pool.prepareNext(Fixture.episode(id: "e2"), atFeedIndex: 1) == true)

        // GEÇİCİ ağ (5xx/timeout) → false (ağ dönünce pencere-içi yeniden ısındırılabilir).
        let transient = makePool()
        transient.service.setFailure(.network(.timeout))
        #expect(await transient.pool.prepareNext(Fixture.episode(id: "e2"), atFeedIndex: 1) == false)

        // self-review4: `.unexpected` (slot-çekişme gibi geçici altyapı) isRetryable=false AMA re-warm edilmeli
        // (sticky-cold olmasın) → false.
        let contention = makePool()
        contention.service.setFailure(.unexpected(underlying: "geri alınabilir slot yok"))
        #expect(await contention.pool.prepareNext(Fixture.episode(id: "e2"), atFeedIndex: 1) == false)
    }

    @Test func warmHitAktivasyondaYenidenYuklemeYapilmaz() async throws {
        // Prefetch isabeti: aynı bölüm slot'ta hazırsa aynı engine döner — cold start yok.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let service = harness.service
        let episode = Fixture.episode(id: "e2")
        await pool.prepareNext(episode, atFeedIndex: 1)
        let authCallsAfterWarm = service.authorizeCallCount

        _ = try await pool.activate(episode, atFeedIndex: 1)

        #expect(service.authorizeCallCount == authCallsAfterWarm) // ikinci authorize yok
        let totalLoads = box.backends.flatMap(\.calls).filter { call in
            if case .load = call {
                return true
            }
            return false
        }.count
        #expect(totalLoads == 1)
        // Aktif hale gelince buffer otomatik moda geçer (04 §4.1 promoteToActive).
        let promoted = box.backends.contains { $0.calls.contains(.applyBufferPolicy(.active)) }
        #expect(promoted)
    }

    @Test func oncekiAktifDemoteEdilir() async throws {
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let first = Fixture.episode(id: "e1")
        let second = Fixture.episode(id: "e2")
        _ = try await pool.activate(first, atFeedIndex: 0)

        _ = try await pool.activate(second, atFeedIndex: 1)

        let firstBackend = box.backends[0]
        #expect(firstBackend.calls.contains(.pause))
        #expect(firstBackend.calls.contains(.applyBufferPolicy(.idle))) // 1 sn'e düşür
    }

    @Test func gecWarmReuseAktifSlotuWarmaDusurmez() async throws {
        // audit HIGH: geç gelen prefetch warm(epX), epX tam aktif slota otururken bu slota inerse rolü
        // .warm yapıp demotePreviousActive'i (role==.active guard'lı) atlatıyor → aktif slot duraklatılmaz
        // → iki slot aynı anda oynar (çift ses). Aktif slot warm-reuse'da .active KALMALI.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let active = Fixture.episode(id: "e1")
        _ = try await pool.activate(active, atFeedIndex: 0)

        await pool.prepareNext(active, atFeedIndex: 0) // aktif bölümün geç warm-reuse'u

        let ids = await pool.snapshotEpisodeIDs()
        let roles = await pool.snapshotRoles()
        let activeIndex = try #require(ids.firstIndex(of: active.id))
        #expect(roles[activeIndex] == .active) // .warm'a düşmemeli

        // Kanıt: sonraki aktife geçişte önceki (hâlâ .active) DURAKLATILIR.
        _ = try await pool.activate(Fixture.episode(id: "e2"), atFeedIndex: 1)
        #expect(box.backends[activeIndex].calls.contains(.pause))
    }

    @Test func doluHavuzdaEnUzakSlotGeriAlinir() async throws {
        let harness = makePool(size: 3)
        let (pool, box) = (harness.pool, harness.box)
        let episodes = Fixture.episodes(count: 5)
        _ = try await pool.activate(episodes[1], atFeedIndex: 1)
        await pool.prepareNext(episodes[0], atFeedIndex: 0)
        await pool.prepareNext(episodes[2], atFeedIndex: 2)

        // Aktif=2'ye ilerle, index 3 için slot gerek: en uzak (index 0) geri alınır.
        _ = try await pool.activate(episodes[2], atFeedIndex: 2)
        await pool.prepareNext(episodes[3], atFeedIndex: 3)

        let ids = await pool.snapshotEpisodeIDs()
        #expect(!ids.contains(EpisodeID("e0")))
        #expect(ids.contains(EpisodeID("e3")))
        #expect(box.backends.count == 3) // yeni player YARATILMAZ (04 §3.3 kural 1)
    }

    @Test func kilitliBolumActivateEdilemez() async {
        let pool = makePool().pool
        let locked = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)

        await #expect(throws: AppError.self) {
            _ = try await pool.activate(locked, atFeedIndex: 0)
        }
    }

    @Test func entitlementVarsaKilitliBolumOynar() async throws {
        let locked = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)
        let pool = makePool(entitled: [locked.id]).pool

        let handle = try await pool.activate(locked, atFeedIndex: 0)

        #expect(handle.episodeID == locked.id)
    }

    @Test func kilitliBolumPrefetchEdilmez() async {
        // 04 §9.1 kural 4: entitlement olmayan kilitli bölüm ısındırılmaz.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let service = harness.service
        let locked = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)

        await pool.prepareNext(locked, atFeedIndex: 3)

        #expect(service.authorizeCallCount == 0)
        let anyLoad = box.backends.contains { backend in
            backend.calls.contains { call in
                if case .load = call {
                    return true
                }
                return false
            }
        }
        #expect(!anyLoad)
        #expect(await pool.snapshotEpisodeIDs().allSatisfy { $0 == nil })
    }

    @Test func entitlementliKilitliBolumPrefetchEdilir() async {
        let locked = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)
        let harness = makePool(entitled: [locked.id])
        let (pool, service) = (harness.pool, harness.service)

        await pool.prepareNext(locked, atFeedIndex: 3)

        #expect(service.authorizeCallCount == 1)
        #expect(await pool.snapshotEpisodeIDs().contains(locked.id))
    }

    @Test func drainItemlariBirakirPlayerlariKorur() async throws {
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")
        _ = try await pool.activate(episode, atFeedIndex: 0)

        await pool.drain()

        #expect(box.backends[0].calls.contains(.clearItem))
        #expect(await pool.snapshotEpisodeIDs().allSatisfy { $0 == nil })

        // Geri dönüşte aynı engine'ler kullanılır; yeni allocation yok (04 §3 kabul kriteri).
        _ = try await pool.activate(episode, atFeedIndex: 0)
        #expect(box.backends.count == 3)
    }

    @Test func recyclePencereDisiSlotlariBosaltir() async throws {
        let pool = makePool(size: 3).pool
        let episodes = Fixture.episodes(count: 6)
        _ = try await pool.activate(episodes[1], atFeedIndex: 1)
        await pool.prepareNext(episodes[0], atFeedIndex: 0)
        await pool.prepareNext(episodes[2], atFeedIndex: 2)

        await pool.recycle(keeping: 1 ... 2)

        let ids = await pool.snapshotEpisodeIDs()
        #expect(!ids.contains(EpisodeID("e0"))) // pencere dışı boşaltıldı
        #expect(ids.contains(EpisodeID("e1")))
        #expect(ids.contains(EpisodeID("e2")))
    }

    @Test func advanceWindowRolleriGunceller() async throws {
        let pool = makePool(size: 3).pool
        let episodes = Fixture.episodes(count: 3)
        _ = try await pool.activate(episodes[0], atFeedIndex: 0)
        await pool.prepareNext(episodes[1], atFeedIndex: 1)

        await pool.advanceWindow(activeEpisodeID: episodes[1].id, direction: .forward)

        let roles = await pool.snapshotRoles()
        let ids = await pool.snapshotEpisodeIDs()
        let activeIndex = ids.firstIndex(of: episodes[1].id)
        #expect(activeIndex != nil)
        if let activeIndex {
            #expect(roles[activeIndex] == .active)
        }
        let oldIndex = ids.firstIndex(of: episodes[0].id)
        if let oldIndex {
            #expect(roles[oldIndex] == .warm)
        }
    }

    @Test func ayniBolumTekrarActivateEdilirseAyniSlotKullanilir() async throws {
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")
        _ = try await pool.activate(episode, atFeedIndex: 0)

        _ = try await pool.activate(episode, atFeedIndex: 0)

        let loads = box.backends.flatMap(\.calls).filter { call in
            if case .load = call {
                return true
            }
            return false
        }
        #expect(loads.count == 1) // yeniden yükleme yok
    }
}

/// Aktivasyon politikası testleri: warm-hit resume/tazelik (04 §12.2, §6.4 kural 4),
/// bitrate tavanı uygulaması (04 §6.3) ve prefetch iptal hijyeni (03 §7.3).
struct PlayerPoolActivationPolicyTests {
    @Test func warmHitAktivasyondaResumePozisyonunaSeekEdilir() async throws {
        // Devam Et + prefetch isabeti (04 §12.2): resumePosition verilmişse engine o konuma seek etmeli.
        // Warm slot henüz .loading (prepareNext, first-frame gelmemiş) ise doğrudan seek YUTULACAĞINDAN
        // ERTELENİR (audit MEDIUM: devam konumu kaybı) → firstFrameReady olayında uygulanır.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e2")
        await pool.prepareNext(episode, atFeedIndex: 1)

        _ = try await pool.activate(episode, atFeedIndex: 1, resumePosition: 27)

        #expect(!box.backends.contains { $0.calls.contains(.seek(27)) }) // .loading iken doğrudan seek YOK
        box.backends.forEach { $0.emit(.firstFrameReady) }
        let seeked = await eventually { box.backends.contains { $0.calls.contains(.seek(27)) } }
        #expect(seeked) // ilk kare gelince ertelenen seek uygulandı
    }

    @Test func suresiDolmusWarmItemTazeYetkiyleYenidenHazirlanir() async throws {
        // 04 §6.4 kural 4: slot'taki item'ın imzalı URL'i kullanılabilir değilse
        // warm-hit aktivasyonu taze authorize + yeniden hazırlama yoluna düşer.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let service = harness.service
        service.setExpiry(Date(timeIntervalSinceNow: -5)) // ısınan yetki baştan bayat
        let episode = Fixture.episode(id: "e2")
        await pool.prepareNext(episode, atFeedIndex: 1)
        #expect(service.authorizeCallCount == 1)
        service.setExpiry(Date(timeIntervalSinceNow: 600))

        _ = try await pool.activate(episode, atFeedIndex: 1)

        #expect(service.authorizeCallCount == 2) // freshAuthorization çağrıldı
        let freshLoads = box.backends.flatMap(\.calls).filter { call in
            if case let .load(url, _) = call {
                return url.absoluteString.contains("/v2/")
            }
            return false
        }
        #expect(freshLoads.count == 1) // taze imzalı URL ile yeniden yüklendi
    }

    @Test func hucreselVeriTasarrufundaBitrateTavaniUygulanir() async throws {
        // 04 §6.3 kanon: hücresel + veri tasarrufu = 480p tavanı (preferredPeakBitRate).
        let harness = makePool(network: .cellular, dataSaver: true)
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")

        _ = try await pool.activate(episode, atFeedIndex: 0)

        let capped = box.backends.contains {
            $0.calls.contains(.setPeakBitRateCap(BitrateCapPolicy.dataSaverCap))
        }
        #expect(capped)
    }

    @Test func normalHucreselde720pTavaniUygulanir() async throws {
        // 04 §6.3: hücresel (tasarrufsuz) 720p tavanı — remote config varsayılanı.
        let harness = makePool(network: .cellular)
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")

        _ = try await pool.activate(episode, atFeedIndex: 0)

        let capped = box.backends.contains {
            $0.calls.contains(.setPeakBitRateCap(BitrateCapPolicy.cellularCap))
        }
        #expect(capped)
    }

    @Test func wifidaBitrateTavaniKaldirilir() async throws {
        // 04 §6.3: Wi-Fi'da sınır yok — tavan nil ile kaldırılır, ABR karar verir.
        let harness = makePool()
        let (pool, box) = (harness.pool, harness.box)
        let episode = Fixture.episode(id: "e1")

        _ = try await pool.activate(episode, atFeedIndex: 0)

        let uncapped = box.backends.contains { $0.calls.contains(.setPeakBitRateCap(nil)) }
        #expect(uncapped)
    }

    @Test func iptalEdilenPrefetchSlotuTemizBirakir() async {
        // 03 §7.3 / 04 §5.1: authorize sırasında iptal edilen prefetch yarım item bırakmaz.
        let harness = makePool()
        let (pool, service) = (harness.pool, harness.service)
        service.setDelay(nanoseconds: 500_000_000)
        let episode = Fixture.episode(id: "e2")

        let task = Task { await pool.prepareNext(episode, atFeedIndex: 1) }
        try? await Task.sleep(nanoseconds: 50_000_000) // authorize uçuşta
        task.cancel()
        await task.value

        #expect(await pool.snapshotEpisodeIDs().allSatisfy { $0 == nil })
    }
}
