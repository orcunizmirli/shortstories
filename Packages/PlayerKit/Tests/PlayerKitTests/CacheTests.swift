import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

/// LRU eviction saf karar mantığı (04 §7.2): bütçe ~200 MB; en eski erişim önce,
/// izlenmiş (tamamlanmış) bölümler eviction'da önceliklidir.
struct CacheEvictionPlannerTests {
    private func record(
        _ name: String,
        size: Int64,
        accessedAt seconds: TimeInterval,
        watched: Bool = false
    ) -> CacheRecordSnapshot {
        CacheRecordSnapshot(
            url: URL(string: "file:///cache/\(name).movpkg")!,
            sizeInBytes: size,
            lastAccessAt: Date(timeIntervalSince1970: seconds),
            isWatched: watched
        )
    }

    @Test func butceAltindaEvictionYok() {
        let need = CacheEvictionPlanner.bytesToFree(
            totalSizeInBytes: 150, incomingBytes: 40, budgetBytes: 200
        )
        #expect(need == 0)
    }

    @Test func butceAsimindaFarkKadarYerAcilir() {
        let need = CacheEvictionPlanner.bytesToFree(
            totalSizeInBytes: 210, incomingBytes: 30, budgetBytes: 200
        )
        #expect(need == 40)
    }

    @Test func enEskiErisimOnceSecilir() {
        let victims = CacheEvictionPlanner.selectVictims(
            candidates: [
                record("yeni", size: 100, accessedAt: 300),
                record("eski", size: 100, accessedAt: 100),
                record("orta", size: 100, accessedAt: 200)
            ],
            bytesToFree: 150
        )
        #expect(victims.map(\.url.lastPathComponent) == ["eski.movpkg", "orta.movpkg"])
    }

    @Test func izlenmisBolumlerOncelikliTahliyeEdilir() {
        let victims = CacheEvictionPlanner.selectVictims(
            candidates: [
                record("eskiAmaIzlenmemis", size: 100, accessedAt: 100),
                record("yeniAmaIzlenmis", size: 100, accessedAt: 300, watched: true)
            ],
            bytesToFree: 100
        )
        #expect(victims.map(\.url.lastPathComponent) == ["yeniAmaIzlenmis.movpkg"])
    }

    @Test func sifirIhtiyactaBosListeDoner() {
        let victims = CacheEvictionPlanner.selectVictims(
            candidates: [record("kayit", size: 100, accessedAt: 100)],
            bytesToFree: 0
        )
        #expect(victims.isEmpty)
    }
}

/// Ön-indirme uygunluk politikası (04 §7.2): yalnız Wi-Fi, kilitli/entitlement'sız asla.
struct CachePreloadPolicyTests {
    @Test func wifidaSerbestBolumIndirilebilir() {
        let allowed = CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: true, hasEntitlement: false, network: .wifi, isAlreadyCached: false
        )
        #expect(allowed)
    }

    @Test func hucreseldeIndirilmez() {
        let allowed = CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: true, hasEntitlement: false, network: .cellular, isAlreadyCached: false
        )
        #expect(!allowed)
    }

    @Test func kilitliVeEntitlementsizIndirilmez() {
        let allowed = CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: false, hasEntitlement: false, network: .wifi, isAlreadyCached: false
        )
        #expect(!allowed)
    }

    @Test func entitlementliKilitliIndirilebilir() {
        let allowed = CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: false, hasEntitlement: true, network: .wifi, isAlreadyCached: false
        )
        #expect(allowed)
    }

    @Test func zatenCachedeyseTekrarIndirilmez() {
        let allowed = CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: true, hasEntitlement: false, network: .wifi, isAlreadyCached: true
        )
        #expect(!allowed)
    }
}

/// EpisodeCacheStore iskeleti (04 §7.2, SS-043 çekirdek dilimi): AssetCacheIndexing
/// portu üzerinden LRU defteri; indirme protokol arkasında (CI'da gerçek indirme yok).
struct EpisodeCacheStoreTests {
    private struct Harness {
        let store: EpisodeCacheStore
        let index: FakeCacheIndex
        let downloader: FakeDownloader
    }

    private func makeStore(
        budgetBytes: Int64 = EpisodeCacheStore.defaultBudgetBytes,
        assetSize: Int64 = 1000,
        entitled: Set<EpisodeID> = [],
        clock: ClockBox = ClockBox()
    ) -> Harness {
        let index = FakeCacheIndex()
        let downloader = FakeDownloader(assetSizeInBytes: assetSize)
        let store = EpisodeCacheStore(
            cacheIndex: index,
            downloader: downloader,
            budgetBytes: budgetBytes,
            entitlements: FakeEntitlements(granted: entitled),
            logger: MockLogger(),
            now: clock.nowProvider
        )
        return Harness(store: store, index: index, downloader: downloader)
    }

    private func authorization(for episode: ContentKit.Episode) -> PlaybackAuthorization {
        PlaybackAuthorization(
            episodeId: episode.id,
            playbackURL: URL(string: "https://cdn.test/\(episode.id.rawValue)/master.m3u8")!,
            expiresAt: Date().addingTimeInterval(600),
            drm: nil
        )
    }

    @Test func wifidaPreload480pRunguIleIndirir() async {
        let harness = makeStore()
        let (store, index) = (harness.store, harness.index)
        let downloader = harness.downloader
        let episode = Fixture.episode(id: "e1")

        await store.preload(episode, authorization: authorization(for: episode), network: .wifi)

        #expect(downloader.downloads.count == 1)
        #expect(downloader.downloads.first?.minimumBitrate == 800_000) // 480p rung (04 §7.2)
        #expect(index.allRecords.count == 1)
    }

    @Test func hucreseldePreloadYapilmaz() async {
        let harness = makeStore()
        let (store, downloader) = (harness.store, harness.downloader)
        let episode = Fixture.episode(id: "e1")

        await store.preload(episode, authorization: authorization(for: episode), network: .cellular)

        #expect(downloader.downloads.isEmpty)
    }

    @Test func kilitliBolumPreloadEdilmez() async {
        let harness = makeStore()
        let (store, downloader) = (harness.store, harness.downloader)
        let locked = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)

        await store.preload(locked, authorization: authorization(for: locked), network: .wifi)

        #expect(downloader.downloads.isEmpty)
    }

    @Test func indirilenBolumYerelAssetOlarakBulunur() async {
        let store = makeStore().store
        let episode = Fixture.episode(id: "e1")
        await store.preload(episode, authorization: authorization(for: episode), network: .wifi)

        let local = await store.localAsset(for: episode.id)

        #expect(local != nil)
    }

    @Test func yerelAssetErisimiLRUDefterineIslenir() async {
        let clock = ClockBox()
        let harness = makeStore(clock: clock)
        let (store, index) = (harness.store, harness.index)
        let episode = Fixture.episode(id: "e1")
        await store.preload(episode, authorization: authorization(for: episode), network: .wifi)
        clock.advance(by: 100)

        let local = await store.localAsset(for: episode.id)

        #expect(local != nil)
        let record = index.allRecords.first { $0.url == local }
        #expect(record?.lastAccessAt == clock.now) // markAccessed çağrıldı
    }

    @Test func ayniBolumIkinciKezIndirilmez() async {
        let harness = makeStore()
        let (store, downloader) = (harness.store, harness.downloader)
        let episode = Fixture.episode(id: "e1")
        await store.preload(episode, authorization: authorization(for: episode), network: .wifi)

        await store.preload(episode, authorization: authorization(for: episode), network: .wifi)

        #expect(downloader.downloads.count == 1)
    }

    @Test func butceAsilincaEnEskiKayitTahliyeEdilir() async {
        let clock = ClockBox()
        let harness = makeStore(budgetBytes: 1500, assetSize: 600, clock: clock)
        let (store, index) = (harness.store, harness.index)
        let downloader = harness.downloader
        let first = Fixture.episode(id: "e1")
        let second = Fixture.episode(id: "e2")
        let third = Fixture.episode(id: "e3")

        await store.preload(first, authorization: authorization(for: first), network: .wifi)
        clock.advance(by: 10)
        await store.preload(second, authorization: authorization(for: second), network: .wifi)
        clock.advance(by: 10)
        await store.preload(third, authorization: authorization(for: third), network: .wifi)

        // 3 × 600 = 1800 > 1500: en eski (e1) tahliye edilir.
        #expect(!downloader.removedLocalURLs.isEmpty)
        #expect(await store.localAsset(for: first.id) == nil)
        #expect(await store.localAsset(for: third.id) != nil)
        let total = await (try? index.totalSizeInBytes()) ?? -1
        #expect(total <= 1500)
    }
}
