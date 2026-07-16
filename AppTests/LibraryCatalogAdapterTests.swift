import AppFoundation
import ContentKit
import Foundation
import LibraryKit
import XCTest
@testable import ShortSeriesApp

/// `CatalogLibraryReading` (Listem JOIN adaptörü) saf indeks/karar mantığı + offline-önce davranış
/// testleri. Ağ/SwiftData KURULMAZ — stub `CatalogServicing` + in-memory `CatalogCacheStore` ile
/// değer→değer eşlemeleri ve cache-önce kararları doğrulanır. Bu hedef CI'da koşmaz (App target CI
/// dışı) — lokal doğrulama içindir.
final class LibraryCatalogAdapterTests: XCTestCase {
    // MARK: - Saf: episodeID → numara indeksi kurulumu

    func testEpisodeIndexMapsEachEpisodeToItsIndex() {
        let episodes = [
            makeEpisode(id: "e1", series: "s1", index: 1),
            makeEpisode(id: "e2", series: "s1", index: 2),
            makeEpisode(id: "e3", series: "s1", index: 3)
        ]
        let index = CatalogLibraryReading.episodeIndex(from: episodes)
        XCTAssertEqual(index[EpisodeID("e1")], 1)
        XCTAssertEqual(index[EpisodeID("e2")], 2)
        XCTAssertEqual(index[EpisodeID("e3")], 3)
        XCTAssertNil(index[EpisodeID("eX")])
    }

    func testEpisodeIndexEmptyListIsEmpty() {
        XCTAssertTrue(CatalogLibraryReading.episodeIndex(from: []).isEmpty)
    }

    // MARK: - Saf: istenen bölümler için numara seçimi

    func testEpisodeNumbersPicksFromResolvedSeriesIndex() {
        let seriesByEpisode: [EpisodeID: SeriesID] = [
            EpisodeID("e1"): SeriesID("s1"),
            EpisodeID("e2"): SeriesID("s1"),
            EpisodeID("e9"): SeriesID("s2")
        ]
        let indexBySeries: [SeriesID: [EpisodeID: Int]] = [
            SeriesID("s1"): [EpisodeID("e1"): 1, EpisodeID("e2"): 2],
            SeriesID("s2"): [EpisodeID("e9"): 9]
        ]
        let numbers = CatalogLibraryReading.episodeNumbers(
            requested: [EpisodeID("e1"), EpisodeID("e2"), EpisodeID("e9"), EpisodeID("eUnresolved")],
            seriesByEpisode: seriesByEpisode,
            indexBySeries: indexBySeries
        )
        XCTAssertEqual(numbers, [EpisodeID("e1"): 1, EpisodeID("e2"): 2, EpisodeID("e9"): 9])
        // Çözülemeyen ID sözlükte yer almaz.
        XCTAssertNil(numbers[EpisodeID("eUnresolved")])
    }

    // MARK: - Saf: cache-önce okuma kararı (dizi özeti)

    func testCachedSeriesInfoDecisionUsesCacheWhenPayloadDecodable() throws {
        let info = try LibrarySeriesInfo(
            id: SeriesID("s1"),
            title: "Dizi",
            coverURL: XCTUnwrap(URL(string: "https://cdn.example.com/s1.jpg")),
            isAvailable: true
        )
        let cached = try CachedPayload(payload: CatalogLibraryReading.encodeSeriesInfo(info), etag: nil, fetchedAt: Date())
        // Cache hit + decode → özet döner (ağ ATLANIR).
        XCTAssertEqual(CatalogLibraryReading.cachedSeriesInfo(from: cached, id: SeriesID("s1")), info)
    }

    func testCachedSeriesInfoDecisionFallsToNetworkWhenAbsentOrCorrupt() {
        // Cache miss → nil (çağıran ağa gider).
        XCTAssertNil(CatalogLibraryReading.cachedSeriesInfo(from: nil, id: SeriesID("s1")))
        // Bozuk payload → nil (ağa gider).
        let corrupt = CachedPayload(payload: Data("not json".utf8), etag: nil, fetchedAt: Date())
        XCTAssertNil(CatalogLibraryReading.cachedSeriesInfo(from: corrupt, id: SeriesID("s1")))
    }

    // MARK: - Saf: bölüm-listesi cache payload round-trip

    func testEpisodeListPayloadRoundTrip() throws {
        let episodes = [
            makeEpisode(id: "e1", series: "s1", index: 1),
            makeEpisode(id: "e7", series: "s1", index: 7)
        ]
        let data = try CatalogLibraryReading.encodeEpisodeIndex(episodes)
        let cached = CachedPayload(payload: data, etag: nil, fetchedAt: Date())
        let index = try XCTUnwrap(CatalogLibraryReading.cachedEpisodeIndex(from: cached))
        XCTAssertEqual(index[EpisodeID("e1")], 1)
        XCTAssertEqual(index[EpisodeID("e7")], 7)
    }

    func testCachedEpisodeIndexNilWhenAbsentOrCorrupt() {
        XCTAssertNil(CatalogLibraryReading.cachedEpisodeIndex(from: nil))
        let corrupt = CachedPayload(payload: Data("[]not-json".utf8), etag: nil, fetchedAt: Date())
        XCTAssertNil(CatalogLibraryReading.cachedEpisodeIndex(from: corrupt))
    }

    // MARK: - Saf: eşzamanlılık-kapaklı map sırayı korur

    func testMapWithConcurrencyPreservesOrder() async {
        let out = await CatalogLibraryReading.mapWithConcurrency([1, 2, 3, 4, 5], limit: 2) { $0 * 10 }
        XCTAssertEqual(out, [10, 20, 30, 40, 50])
    }

    // MARK: - Entegrasyon: seriesInfo offline-önce (stub katalog + in-memory cache)

    func testSeriesInfoNetworkThenCacheFirst() async {
        let cache = InMemoryCatalogCache()
        let catalog = StubCatalog(series: [SeriesID("s1"): makeSeries(id: "s1", title: "Dizi 1")])
        let adapter = CatalogLibraryReading(catalog: catalog, cache: cache, resolveSeries: { _ in [:] })

        // 1. çağrı: cache miss → ağdan çek + cache'e yaz.
        let first = await adapter.seriesInfo(ids: [SeriesID("s1")])
        XCTAssertEqual(first[SeriesID("s1")]?.title, "Dizi 1")
        let callsAfterFirst = await catalog.seriesDetailCallCount
        XCTAssertEqual(callsAfterFirst, 1)

        // 2. çağrı: cache hit → ağ ATLANIR (çağrı sayısı artmaz).
        let second = await adapter.seriesInfo(ids: [SeriesID("s1")])
        XCTAssertEqual(second[SeriesID("s1")]?.title, "Dizi 1")
        let callsAfterSecond = await catalog.seriesDetailCallCount
        XCTAssertEqual(callsAfterSecond, 1)
    }

    func testSeriesInfoServesCacheWhenOffline() async {
        let cache = InMemoryCatalogCache()
        // Önce online adaptör cache'i doldurur.
        let online = CatalogLibraryReading(
            catalog: StubCatalog(series: [SeriesID("s1"): makeSeries(id: "s1", title: "Dizi 1")]),
            cache: cache,
            resolveSeries: { _ in [:] }
        )
        _ = await online.seriesInfo(ids: [SeriesID("s1")])

        // Offline adaptör aynı cache ile: ağ patlar ama cache'ten döner (02 §4.12).
        let offline = CatalogLibraryReading(catalog: StubCatalog(offline: true), cache: cache, resolveSeries: { _ in [:] })
        let infos = await offline.seriesInfo(ids: [SeriesID("s1")])
        XCTAssertEqual(infos[SeriesID("s1")]?.title, "Dizi 1")
    }

    func testSeriesInfoDropsSeriesWhenOfflineAndUncached() async {
        let adapter = CatalogLibraryReading(
            catalog: StubCatalog(offline: true),
            cache: InMemoryCatalogCache(),
            resolveSeries: { _ in [:] }
        )
        let infos = await adapter.seriesInfo(ids: [SeriesID("s1")])
        // Ağ da cache de yok → kayıt düşer (çağıran isAvailable=false varsayar).
        XCTAssertTrue(infos.isEmpty)
    }

    // MARK: - Entegrasyon: episodeNumbers dizi bağlamını çözer + indeks kurar

    func testEpisodeNumbersResolvesSeriesAndBuildsIndex() async {
        let cache = InMemoryCatalogCache()
        let catalog = StubCatalog(
            series: [:],
            episodesBySeries: [
                SeriesID("s1"): [
                    makeEpisode(id: "e1", series: "s1", index: 1),
                    makeEpisode(id: "e2", series: "s1", index: 2)
                ]
            ]
        )
        let adapter = CatalogLibraryReading(
            catalog: catalog,
            cache: cache,
            resolveSeries: { ids in
                // Continue-watching çözümü: e1/e2 → s1; bilinmeyen çözülmez.
                Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (EpisodeID, SeriesID)? in
                    id == EpisodeID("e1") || id == EpisodeID("e2") ? (id, SeriesID("s1")) : nil
                })
            }
        )

        let numbers = await adapter.episodeNumbers(ids: [EpisodeID("e1"), EpisodeID("e2"), EpisodeID("eX")])
        XCTAssertEqual(numbers[EpisodeID("e1")], 1)
        XCTAssertEqual(numbers[EpisodeID("e2")], 2)
        XCTAssertNil(numbers[EpisodeID("eX")]) // çözülemeyen ID
        let listCallsAfterFirst = await catalog.episodeListCallCount
        XCTAssertEqual(listCallsAfterFirst, 1)

        // 2. çağrı: bölüm listesi cache'ten → ağ tekrar çekmez.
        _ = await adapter.episodeNumbers(ids: [EpisodeID("e1")])
        let listCallsAfterSecond = await catalog.episodeListCallCount
        XCTAssertEqual(listCallsAfterSecond, 1)
    }

    func testEpisodeNumbersEmptyWhenNoSeriesResolved() async {
        let adapter = CatalogLibraryReading(
            catalog: StubCatalog(),
            cache: InMemoryCatalogCache(),
            resolveSeries: { _ in [:] }
        )
        let numbers = await adapter.episodeNumbers(ids: [EpisodeID("e1")])
        XCTAssertTrue(numbers.isEmpty)
    }

    // MARK: - Fixtures

    private func makeEpisode(id: String, series: String, index: Int) -> Episode {
        Episode(
            id: EpisodeID(id),
            seriesId: SeriesID(series),
            index: index,
            title: nil,
            durationSec: 90,
            thumbnailURL: URL(string: "https://cdn.example.com/\(id).jpg")!,
            access: EpisodeAccess(kind: .free, unlockPrice: nil, adUnlockEligible: false),
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSeries(id: String, title: String) -> Series {
        Series(
            id: SeriesID(id),
            title: title,
            synopsis: "…",
            coverURL: URL(string: "https://cdn.example.com/\(id).jpg")!,
            bannerURL: nil,
            genres: [],
            tags: [],
            episodeCount: 10,
            releasedEpisodeCount: 10,
            freeEpisodeCount: 3,
            releaseState: .completed,
            nextEpisodeAt: nil,
            stats: SeriesStats(viewCount: 0, favoriteCount: 0, trendingRank: nil),
            localeInfo: LocaleInfo(audioLanguage: "en", subtitleLanguages: ["en"]),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - Test stub'ları

/// Çağrı sayan stub `CatalogServicing`. `offline=true` iken her çağrı `AppError.network(.offline)` atar.
private actor StubCatalog: CatalogServicing {
    private let series: [SeriesID: Series]
    private let episodesBySeries: [SeriesID: [Episode]]
    private let pageSize: Int
    private let offline: Bool
    private(set) var seriesDetailCallCount = 0
    private(set) var episodeListCallCount = 0

    init(
        series: [SeriesID: Series] = [:],
        episodesBySeries: [SeriesID: [Episode]] = [:],
        pageSize: Int = 100,
        offline: Bool = false
    ) {
        self.series = series
        self.episodesBySeries = episodesBySeries
        self.pageSize = pageSize
        self.offline = offline
    }

    func seriesDetail(id: SeriesID) async throws -> Series {
        seriesDetailCallCount += 1
        if offline {
            throw AppError.network(.offline)
        }
        guard let match = series[id] else { throw AppError.network(.server(status: 404)) }
        return match
    }

    func episodes(seriesId: SeriesID, cursor: String?) async throws -> Page<Episode> {
        episodeListCallCount += 1
        if offline {
            throw AppError.network(.offline)
        }
        let all = episodesBySeries[seriesId] ?? []
        let start = cursor.flatMap { Int($0) } ?? 0
        let end = min(start + pageSize, all.count)
        let slice = start < end ? Array(all[start ..< end]) : []
        let next = end < all.count ? String(end) : nil
        return Page(items: slice, nextCursor: next, ttlSec: nil)
    }

    func discover() async throws -> DiscoverContent {
        throw AppError.network(.offline)
    }

    func collectionPage(id _: String, cursor _: String?) async throws -> Page<Series> {
        throw AppError.network(.offline)
    }
}

/// Sürüm-farkında in-memory `CatalogCacheStore` (SwiftData'sız; testler yan etkisiz).
private actor InMemoryCatalogCache: CatalogCacheStore {
    private var seriesEntries: [String: (payload: Data, version: Int)] = [:]
    private var episodeEntries: [String: (payload: Data, version: Int)] = [:]

    func cachedSeries(id: SeriesID, expectedSchemaVersion: Int) throws -> CachedPayload? {
        entry(seriesEntries[id.rawValue], expected: expectedSchemaVersion) { seriesEntries[id.rawValue] = nil }
    }

    func storeSeries(id: SeriesID, payload: Data, schemaVersion: Int, etag _: String?, fetchedAt _: Date) throws {
        seriesEntries[id.rawValue] = (payload, schemaVersion)
    }

    func cachedEpisodeList(seriesID: SeriesID, expectedSchemaVersion: Int) throws -> CachedPayload? {
        entry(episodeEntries[seriesID.rawValue], expected: expectedSchemaVersion) { episodeEntries[seriesID.rawValue] = nil }
    }

    func storeEpisodeList(
        seriesID: SeriesID,
        payload: Data,
        schemaVersion: Int,
        etag _: String?,
        fetchedAt _: Date
    ) throws {
        episodeEntries[seriesID.rawValue] = (payload, schemaVersion)
    }

    func cachedFeedSnapshot(key _: String, expectedSchemaVersion _: Int) throws -> CachedPayload? {
        nil
    }

    func storeFeedSnapshot(key _: String, payload _: Data, schemaVersion _: Int, fetchedAt _: Date) throws {}

    func evictCatalogCacheIfNeeded() throws -> Int {
        0
    }

    private func entry(
        _ stored: (payload: Data, version: Int)?,
        expected: Int,
        purge: () -> Void
    ) -> CachedPayload? {
        guard let stored else { return nil }
        guard stored.version == expected else {
            purge()
            return nil
        }
        return CachedPayload(payload: stored.payload, etag: nil, fetchedAt: Date())
    }
}
