import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

/// Self-review MEDIUM (dead-button regresyonu): paywall fix'i (798ab0b), CTA hedef Episode yüklenemezse
/// (sonraki sayfa fetch HATASI) ctaLocked'ı güvenli-taraf true yapıyor AMA primaryCTA sessiz no-op olup
/// ÖLÜ buton bırakıyordu. Fix: hedef yüklü değilse startWatching'e düş (server-otoriter oynatma; entitled
/// oynar, kilitliyse feed paywall gösterir — sessiz kilitleme değil).
@MainActor
@Suite("DiziDetay CTA fallback (dead-button regresyonu)")
struct DiziDetayCTAFallbackTests {
    @Test func ctaTargetPageFetchFailureFallsBackToStartWatchingNotDeadButton() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: 60, freeEpisodeCount: 5
        )))
        let page1 = (1 ... 30).map { Fixtures.episode(seriesID: "srs_abc123", index: $0, access: .free) }
        spy.setEpisodes(.success(Page(items: page1, nextCursor: "p2", ttlSec: nil)))
        spy.setEpisodesPage(.failure(.network(.offline)), cursor: "p2") // hedef bölüm 31 YÜKLENEMEZ
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 30, completed: true))
        let delegate = DiziDetayDelegateSpy()
        let model = DiziDetayModel(
            seriesID: SeriesID("srs_abc123"),
            source: .kesfet,
            catalog: spy,
            history: history,
            favorites: FakeFavorites(),
            entitlement: FakeEntitlements(),
            analytics: MockAnalytics(),
            delegate: delegate,
            now: { now }
        )
        await model.load()

        #expect(model.ctaTarget?.episodeNumber == 31)
        #expect(model.ctaLocked) // hedef yüklenemedi → güvenli-taraf kilitli (ikon)
        model.primaryCTA()
        #expect(delegate.unlockIntents.isEmpty) // intent kurulamaz (episode yüklü değil)
        #expect(delegate.started.first?.episodeNumber == 31) // ölü buton DEĞİL → startWatching (backstop)
    }
}
