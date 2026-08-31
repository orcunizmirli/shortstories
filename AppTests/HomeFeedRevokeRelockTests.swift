import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import PlayerKit
import XCTest
@testable import ShortSeriesApp

/// SS #4 VIP-expiry/iade IN-SESSION re-lock: `HomeCoordinator` entitlement-DÜŞÜŞÜNDE, client-optimistik
/// (`applyUnlock`/`applyVIPUnlock`) `.unlocked` işaretlenip erişimi KALMAYAN bölümleri feed'de geri `.locked`
/// yapar → `PlayerPool.isPlayable` yeniden `hasAccess`'e düşer (paywall geri gelir; sızıntı kapanır).
/// Katalog-historik `.unlocked` (izlenmez; `WalletStore.unlockedEpisodes` oturum-yerel → hasAccess'te YOK)
/// DOKUNULMAZ → geçmiş-oturum satın-alması false-lock OLMAZ. `revertRevokedOptimisticUnlocks` doğrudan
/// sürülür (gözlemci akışı `accountObserver` deseninin aynısı; App target CI dışı → yerel doğrulanır).
@MainActor
final class HomeFeedRevokeRelockTests: XCTestCase {
    func testRevokedClientOptimisticUnlockIsRelockedInFeed() async throws {
        let home = try makeHome()
        home.feedViewModel.feedState = FeedState(items: [makeItem(episode: "e1", kind: .locked, unlockPrice: 50)])
        home.applyUnlock(EpisodeID("e1")) // client-optimistik açar + izler
        XCTAssertEqual(home.feedViewModel.feedState.items.first?.episode?.access.kind, .unlocked)

        // Entitlement düşüşü: e1'e erişim yok (VIP-expiry/iade) → re-lock beklenir.
        await home.revertRevokedOptimisticUnlocks(entitlement: MockEntitlement(accessible: []))

        XCTAssertEqual(home.feedViewModel.feedState.items.first?.episode?.access.kind, .locked)
        XCTAssertEqual(home.feedViewModel.feedState.items.first?.episode?.access.unlockPrice, 50) // CTA fiyatı korunur
    }

    func testHistoricalCatalogUnlockedIsNotRelocked() async throws {
        // KRİTİK false-lock koruması: server-katalog `.unlocked` (izlenmez; oturum-yerel hasAccess'te YOK)
        // entitlement-düşüşünde DOKUNULMAMALI → geçmiş-oturum satın-alması kilitlenmez.
        let home = try makeHome()
        home.feedViewModel.feedState = FeedState(items: [makeItem(episode: "e9", kind: .unlocked)]) // izlenmeyen
        XCTAssertTrue(home.clientOptimisticUnlocks.isEmpty)

        await home.revertRevokedOptimisticUnlocks(entitlement: MockEntitlement(accessible: []))

        XCTAssertEqual(home.feedViewModel.feedState.items.first?.episode?.access.kind, .unlocked) // korundu
    }

    func testCoinOwnedStaysWhileVIPOnlyRevokedRelocks() async throws {
        // VIP tüm kilitlileri açar (izlenir). VIP-expiry'de: coin-owned (hasAccess true) KALIR, salt-VIP KİLİTLENİR.
        let home = try makeHome()
        home.feedViewModel.feedState = FeedState(items: [
            makeItem(episode: "e1", kind: .locked, unlockPrice: 50),
            makeItem(episode: "e2", kind: .locked, unlockPrice: 50)
        ])
        home.applyVIPUnlock() // ikisini de açar + izler
        XCTAssertEqual(home.feedViewModel.feedState.items.map { $0.episode?.access.kind }, [.unlocked, .unlocked])

        // VIP-expiry: e2 coin-owned (hasAccess true), e1 salt-VIP (false).
        await home.revertRevokedOptimisticUnlocks(entitlement: MockEntitlement(accessible: [EpisodeID("e2")]))

        XCTAssertEqual(home.feedViewModel.feedState.items[0].episode?.access.kind, .locked) // salt-VIP → kilitlendi
        XCTAssertEqual(home.feedViewModel.feedState.items[1].episode?.access.kind, .unlocked) // coin-owned → kaldı
    }

    // MARK: - Fixtures

    private func makeHome() throws -> HomeCoordinator {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        return tab.home
    }

    private func makeItem(episode episodeID: String, kind: EpisodeAccess.Kind, unlockPrice: Int? = nil) -> FeedItem {
        let episode = Episode(
            id: EpisodeID(episodeID),
            seriesId: SeriesID("s1"),
            index: 1,
            title: nil,
            durationSec: 90,
            thumbnailURL: URL(string: "https://cdn.example.com/\(episodeID).jpg")!,
            access: EpisodeAccess(kind: kind, unlockPrice: unlockPrice, adUnlockEligible: false),
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        return FeedItem(
            id: "seed-\(episodeID)",
            type: .episode,
            episode: episode,
            series: makeSeries(),
            progress: nil,
            reason: nil
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

/// Kontrollü `EntitlementChecking`: yalnız `accessible` kümesindeki bölümlere erişim verir (VIP-expiry/coin-owned
/// senaryolarını deterministik kılar).
private struct MockEntitlement: EntitlementChecking {
    let accessible: Set<EpisodeID>
    func hasAccess(to episodeID: EpisodeID) async -> Bool {
        accessible.contains(episodeID)
    }
}
