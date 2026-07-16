import AppFoundation
import ContentKit
import Foundation
import XCTest
@testable import ShortSeriesApp

/// SS-050/062 kilitli-bölüm unlock → feed reactivation'ın SAF karar katmanı testleri:
/// `FeedUnlockReducer` verilen `episodeID` için feed öğelerini "oynatılabilir" (`.unlocked`)
/// işaretler. Bu karar `HomeCoordinator.applyUnlock`'un ürettiği yeni `feedState`'in çekirdeğidir;
/// PlayerKit `PlayerFeedViewController.apply(state:)` içindeki `reactivatableUnlockIndex` kilitli
/// kartı bu geçişte (access `.locked` → oynatılabilir) yerinde reactivate eder (04 §9.2). Ağ/
/// SwiftData/PlayerKit koreografisi KURULMAZ — değer→değer karar doğrulanır (App target CI dışı).
final class FeedUnlockReducerTests: XCTestCase {
    // MARK: - Kilitli bölüm → oynatılabilir

    func testUnlockingLockedEpisodeMarksItPlayable() {
        let items = [makeItem(episode: "e1", index: 1, kind: .locked, unlockPrice: 50)]
        let updated = FeedUnlockReducer.applyingUnlock(of: EpisodeID("e1"), to: items)

        XCTAssertEqual(updated?.first?.episode?.access.kind, .unlocked)
        // Reactivation'ın anahtar sinyali: access artık kilitsiz oynatılabilir (04 §9.2).
        XCTAssertEqual(updated?.first?.episode?.access.isPlayableWithoutUnlock, true)
    }

    func testUnlockingPreservesItemAndEpisodeFields() {
        let items = [makeItem(
            id: "seed-e1",
            episode: "e1",
            index: 4,
            kind: .locked,
            unlockPrice: 80,
            adUnlockEligible: true,
            progress: WatchProgress(
                episodeId: EpisodeID("e1"),
                seriesId: SeriesID("s1"),
                positionSec: 12,
                durationSec: 90,
                completed: false,
                watchedAt: Date(timeIntervalSince1970: 0)
            ),
            reason: "Romantik izlediğin için"
        )]
        let updated = FeedUnlockReducer.applyingUnlock(of: EpisodeID("e1"), to: items)
        let item = updated?.first

        // Öğe kimliği/bağlamı KORUNUR: aynı id → diff'li apply reconfigure eder (remount değil).
        XCTAssertEqual(item?.id, "seed-e1")
        XCTAssertEqual(item?.type, .episode)
        XCTAssertEqual(item?.progress?.positionSec, 12)
        XCTAssertEqual(item?.reason, "Romantik izlediğin için")
        // Bölümün oynatma-dışı alanları KORUNUR; yalnız access.kind değişir.
        XCTAssertEqual(item?.episode?.index, 4)
        XCTAssertEqual(item?.episode?.durationSec, 90)
        XCTAssertEqual(item?.episode?.access.unlockPrice, 80)
        XCTAssertEqual(item?.episode?.access.adUnlockEligible, true)
    }

    func testUnlockingOnlyAffectsMatchingEpisode() {
        let items = [
            makeItem(episode: "e1", index: 1, kind: .locked, unlockPrice: 50),
            makeItem(episode: "e2", index: 2, kind: .locked, unlockPrice: 50),
            makeItem(episode: "e3", index: 3, kind: .free)
        ]
        let updated = FeedUnlockReducer.applyingUnlock(of: EpisodeID("e2"), to: items)

        XCTAssertEqual(updated?[0].episode?.access.kind, .locked) // dokunulmaz
        XCTAssertEqual(updated?[1].episode?.access.kind, .unlocked) // açıldı
        XCTAssertEqual(updated?[2].episode?.access.kind, .free) // dokunulmaz
    }

    // MARK: - No-op: değişiklik yok → nil (feedState'e dokunulmaz)

    func testUnlockingAlreadyPlayableEpisodeReturnsNil() {
        // Idempotent: zaten oynatılabilir bölüm için yeniden unlock feed'i güncellemez
        // (tekrar `apply(state:)` + gereksiz reactivation tetiklenmez).
        for kind: EpisodeAccess.Kind in [.free, .unlocked] {
            let items = [makeItem(episode: "e1", index: 1, kind: kind)]
            XCTAssertNil(FeedUnlockReducer.applyingUnlock(of: EpisodeID("e1"), to: items))
        }
    }

    func testUnlockingAbsentEpisodeReturnsNil() {
        let items = [makeItem(episode: "e1", index: 1, kind: .locked, unlockPrice: 50)]
        XCTAssertNil(FeedUnlockReducer.applyingUnlock(of: EpisodeID("e-absent"), to: items))
    }

    func testUnlockingIgnoresItemsWithoutEpisode() {
        // seriesPromo/ara kart (episode == nil): eşleşme yok → nil, feed'e dokunulmaz.
        let items = [makeItem(id: "promo-1", episode: nil, index: 0, kind: .free)]
        XCTAssertNil(FeedUnlockReducer.applyingUnlock(of: EpisodeID("e1"), to: items))
    }

    func testUnlockingEmptyFeedReturnsNil() {
        XCTAssertNil(FeedUnlockReducer.applyingUnlock(of: EpisodeID("e1"), to: []))
    }

    // MARK: - Fixtures

    private func makeItem(
        id: String? = nil,
        episode episodeID: String?,
        index: Int,
        kind: EpisodeAccess.Kind,
        unlockPrice: Int? = nil,
        adUnlockEligible: Bool = false,
        progress: WatchProgress? = nil,
        reason: String? = nil
    ) -> FeedItem {
        let episode = episodeID.map {
            Episode(
                id: EpisodeID($0),
                seriesId: SeriesID("s1"),
                index: index,
                title: nil,
                durationSec: 90,
                thumbnailURL: URL(string: "https://cdn.example.com/\($0).jpg")!,
                access: EpisodeAccess(kind: kind, unlockPrice: unlockPrice, adUnlockEligible: adUnlockEligible),
                publishedAt: Date(timeIntervalSince1970: 0)
            )
        }
        return FeedItem(
            id: id ?? "seed-\(episodeID ?? "promo")",
            type: episode == nil ? .seriesPromo : .episode,
            episode: episode,
            series: makeSeries(),
            progress: progress,
            reason: reason
        )
    }

    private func makeSeries() -> Series {
        Series(
            id: SeriesID("s1"),
            title: "Dizi s1",
            synopsis: "…",
            coverURL: URL(string: "https://cdn.example.com/s1.jpg")!,
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
