import AppFoundation
import ContentKit
import Foundation
import PlayerKit
import XCTest
@testable import ShortSeriesApp

/// SS-062 feed intent wiring + SS-065 "kaldığın yerden devam" SAF mantık testleri: intent→feed-entry
/// eşlemesi (`PlaybackIntentMapper`), katalog çözümü (`PlaybackFeedResolver`, stub katalogla) ve
/// devam-et banner görünürlük kararı (`ContinueWatchingEntryModel.entry`). Ağ/SwiftData/PlayerKit
/// koreografisi KURULMAZ — değer→değer eşlemeler doğrulanır. Bu hedef CI'da koşmaz (App target CI dışı).
final class PlaybackFeedSeedTests: XCTestCase {
    // MARK: - SAF: intent → hedef bölüm ID'si

    func testTargetEpisodeIDPrefersResolvedEpisodeIDOverNumber() {
        let intent = HomeCoordinator.PlaybackIntent(
            seriesID: SeriesID("s1"),
            episodeNumber: 2,
            episodeID: EpisodeID("e-explicit")
        )
        // Önceden çözülmüş episodeID, episodeNumber'a göre önceliklidir (devam-et kayıtları taşır).
        XCTAssertEqual(
            PlaybackIntentMapper.targetEpisodeID(for: intent, in: episodes(count: 5)),
            EpisodeID("e-explicit")
        )
    }

    func testTargetEpisodeIDResolvesNumberByOneBasedIndex() {
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"), episodeNumber: 3)
        XCTAssertEqual(
            PlaybackIntentMapper.targetEpisodeID(for: intent, in: episodes(count: 5)),
            EpisodeID("e3")
        )
    }

    func testTargetEpisodeIDNilWhenBareIntent() {
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"))
        XCTAssertNil(PlaybackIntentMapper.targetEpisodeID(for: intent, in: episodes(count: 5)))
    }

    func testTargetEpisodeIDNilWhenNumberAbsent() {
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"), episodeNumber: 99)
        XCTAssertNil(PlaybackIntentMapper.targetEpisodeID(for: intent, in: episodes(count: 5)))
    }

    // MARK: - SAF: intent → FeedEntry

    func testMakeEntryPassesSeriesEpisodeAndPosition() {
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"), startPositionSec: 42.5)
        let entry = PlaybackIntentMapper.makeEntry(for: intent, resolvedEpisodeID: EpisodeID("e3"))
        XCTAssertEqual(entry.seriesID, SeriesID("s1"))
        XCTAssertEqual(entry.episodeID, EpisodeID("e3"))
        XCTAssertEqual(entry.startPositionSeconds, 42.5)
    }

    func testMakeEntryClampsNegativePositionToZero() {
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"), startPositionSec: -10)
        let entry = PlaybackIntentMapper.makeEntry(for: intent, resolvedEpisodeID: nil)
        // FeedEntry init negatifi 0'a kırpar; episodeID nil taşınır.
        XCTAssertEqual(entry.startPositionSeconds, 0)
        XCTAssertNil(entry.episodeID)
    }

    // MARK: - SAF: devam-et → intent

    func testContinueIntentCarriesEpisodeIDAndPosition() {
        let intent = PlaybackIntentMapper.continueIntent(
            seriesID: SeriesID("s1"),
            episodeID: EpisodeID("e7"),
            positionSec: 55
        )
        XCTAssertEqual(intent.seriesID, SeriesID("s1"))
        XCTAssertEqual(intent.episodeID, EpisodeID("e7"))
        XCTAssertNil(intent.episodeNumber) // numara lookup'ı yok — kayıt bölümü doğrudan taşır
        XCTAssertEqual(intent.startPositionSec, 55)
    }

    // MARK: - SAF: bölüm → feed öğesi

    func testMakeFeedItemShape() {
        let series = makeSeries(id: "s1")
        let episode = makeEpisode(id: "e3", series: "s1", index: 3)
        let item = PlaybackIntentMapper.makeFeedItem(series: series, episode: episode)
        XCTAssertEqual(item.id, "seed-e3")
        XCTAssertEqual(item.type, .episode)
        XCTAssertEqual(item.episode, episode)
        XCTAssertEqual(item.series, series)
        // progress bilinçli nil: başlangıç konumu tek kanaldan (FeedEntry override) taşınır.
        XCTAssertNil(item.progress)
        XCTAssertNil(item.reason)
    }

    // MARK: - Çözümleyici: numaraya göre seed

    func testResolveByEpisodeNumberBuildsEntryAndItems() async {
        let catalog = StubCatalog(
            series: [SeriesID("s1"): makeSeries(id: "s1")],
            episodesBySeries: [SeriesID("s1"): episodes(count: 5)]
        )
        let resolver = PlaybackFeedResolver(catalog: catalog)
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"), episodeNumber: 4, startPositionSec: 12)

        let seed = await resolver.resolve(intent)
        XCTAssertEqual(seed?.entry.episodeID, EpisodeID("e4"))
        XCTAssertEqual(seed?.entry.startPositionSeconds, 12)
        XCTAssertEqual(seed?.items.count, 5)
        // Seed öğeleri hedef bölümü İÇERİR (yoksa FeedSeedPolicy çözemez).
        XCTAssertTrue(seed?.items.contains { $0.episode?.id == EpisodeID("e4") } ?? false)
    }

    // MARK: - Çözümleyici: episodeID ilk sayfada değilse sayfalar

    func testResolveByEpisodeIDPagesUntilTargetFound() async {
        let catalog = StubCatalog(
            series: [SeriesID("s1"): makeSeries(id: "s1")],
            episodesBySeries: [SeriesID("s1"): episodes(count: 6)],
            pageSize: 2
        )
        let resolver = PlaybackFeedResolver(catalog: catalog)
        // e5 üçüncü sayfada (index 4): [e1,e2] [e3,e4] [e5,e6].
        let intent = PlaybackIntentMapper.continueIntent(
            seriesID: SeriesID("s1"),
            episodeID: EpisodeID("e5"),
            positionSec: 30
        )

        let seed = await resolver.resolve(intent)
        XCTAssertEqual(seed?.entry.episodeID, EpisodeID("e5"))
        XCTAssertEqual(seed?.entry.startPositionSeconds, 30)
        XCTAssertTrue(seed?.items.contains { $0.episode?.id == EpisodeID("e5") } ?? false)
        let pages = await catalog.episodeListCallCount
        XCTAssertEqual(pages, 3) // hedef bulunana kadar üç sayfa
    }

    // MARK: - Çözümleyici: çıplak .play → ilk oynatılabilir bölüm, tek sayfa

    func testResolveBareIntentPicksFirstPlayableFromSinglePage() async {
        let lockedThenFree = [
            makeEpisode(id: "e1", series: "s1", index: 1, playable: false),
            makeEpisode(id: "e2", series: "s1", index: 2, playable: true)
        ]
        let catalog = StubCatalog(
            series: [SeriesID("s1"): makeSeries(id: "s1")],
            episodesBySeries: [SeriesID("s1"): lockedThenFree]
        )
        let resolver = PlaybackFeedResolver(catalog: catalog)
        let intent = HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1"))

        let seed = await resolver.resolve(intent)
        XCTAssertEqual(seed?.entry.episodeID, EpisodeID("e2")) // ilk oynatılabilir (e1 kilitli)
        let pages = await catalog.episodeListCallCount
        XCTAssertEqual(pages, 1) // çıplak intent ilk sayfayla yetinir
    }

    // MARK: - Çözümleyici: hata/boş durumlar → nil (feed'e dokunulmaz)

    func testResolveNilWhenSeriesMissing() async {
        let resolver = PlaybackFeedResolver(catalog: StubCatalog()) // dizi yok → 404
        let seed = await resolver.resolve(HomeCoordinator.PlaybackIntent(seriesID: SeriesID("sX")))
        XCTAssertNil(seed)
    }

    func testResolveNilWhenOffline() async {
        let resolver = PlaybackFeedResolver(catalog: StubCatalog(offline: true))
        let seed = await resolver.resolve(HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1")))
        XCTAssertNil(seed)
    }

    func testResolveNilWhenSeriesHasNoEpisodes() async {
        let catalog = StubCatalog(series: [SeriesID("s1"): makeSeries(id: "s1")], episodesBySeries: [:])
        let resolver = PlaybackFeedResolver(catalog: catalog)
        let seed = await resolver.resolve(HomeCoordinator.PlaybackIntent(seriesID: SeriesID("s1")))
        XCTAssertNil(seed)
    }

    // MARK: - SS-065: devam-et banner görünürlük + değer kararı (SAF)

    func testContinueEntryNilWhenRecordCompleted() {
        let record = makeRecord(position: 90, duration: 90, completed: true)
        XCTAssertNil(ContinueWatchingEntryModel.entry(from: record, title: "Dizi"))
    }

    func testContinueEntryBuiltWhenIncomplete() {
        let record = makeRecord(position: 45, duration: 90, completed: false)
        let entry = ContinueWatchingEntryModel.entry(from: record, title: "Dizi")
        XCTAssertEqual(entry?.title, "Dizi")
        XCTAssertEqual(entry?.episodeID, record.episodeID)
        XCTAssertEqual(entry?.positionSec, 45)
        XCTAssertEqual(entry?.progressFraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(entry?.progressPercent, 50)
    }

    func testContinueEntryZeroDurationYieldsZeroFraction() {
        let record = makeRecord(position: 10, duration: 0, completed: false)
        XCTAssertEqual(ContinueWatchingEntryModel.entry(from: record, title: "Dizi")?.progressFraction, 0)
    }

    func testContinueEntryClampsOverflowFractionToOne() {
        // Bozuk kayıt (pozisyon > süre) → oran 1'e kırpılır (sıfıra/aşırıya karşı koruma).
        let record = makeRecord(position: 200, duration: 90, completed: false)
        XCTAssertEqual(ContinueWatchingEntryModel.entry(from: record, title: "Dizi")?.progressFraction, 1)
    }

    // MARK: - Fixtures

    private func episodes(count: Int) -> [Episode] {
        (1 ... count).map { makeEpisode(id: "e\($0)", series: "s1", index: $0) }
    }

    private func makeEpisode(id: String, series: String, index: Int, playable: Bool = true) -> Episode {
        Episode(
            id: EpisodeID(id),
            seriesId: SeriesID(series),
            index: index,
            title: nil,
            durationSec: 90,
            thumbnailURL: URL(string: "https://cdn.example.com/\(id).jpg")!,
            access: EpisodeAccess(kind: playable ? .free : .locked, unlockPrice: playable ? nil : 50, adUnlockEligible: false),
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSeries(id: String) -> Series {
        Series(
            id: SeriesID(id),
            title: "Dizi \(id)",
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

    private func makeRecord(position: Double, duration: Double, completed: Bool) -> WatchProgressRecord {
        WatchProgressRecord(
            episodeID: EpisodeID("e1"),
            seriesID: SeriesID("s1"),
            positionSec: position,
            durationSec: duration,
            completed: completed,
            watchedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - Stub katalog (çağrı sayan; cursor = başlangıç indeksi)

/// Çağrı sayan stub `CatalogServicing`. `offline=true` → her çağrı `AppError.network(.offline)`.
/// `pageSize` bölüm-listesi sayfalamasını taklit eder (cursor = string başlangıç indeksi).
private actor StubCatalog: CatalogServicing {
    private let series: [SeriesID: Series]
    private let episodesBySeries: [SeriesID: [Episode]]
    private let pageSize: Int
    private let offline: Bool
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
