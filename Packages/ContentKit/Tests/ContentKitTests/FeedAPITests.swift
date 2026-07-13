import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ContentKit

/// FeedAPI davranış testleri — yalnız DOMAIN adları kullanılır (05 §12 kural 6).
struct FeedAPITests {
    private let mock = MockAPIClient()
    private var api: FeedAPI {
        FeedAPI(client: mock)
    }

    @Test func ilkSayfaCursorsuzIstenir() async throws {
        try mock.stub("/feed", with: .success(Fixtures.data("feed_page")))

        let page = try await api.fetchPage(cursor: nil, limit: nil)

        #expect(page.items.count == 2)
        #expect(page.nextCursor == "eyJvZmZzZXQiOiIxMCJ9")
        #expect(page.ttlSec == 300)
        let endpoint = try #require(mock.receivedEndpoints.first as? FeedEndpoint)
        #expect(endpoint.query.isEmpty)
    }

    /// Cursor sayfalama davranışı: istemci cursor'ı yorumlamaz, aynen geri gönderir (05 §7.1).
    @Test func sonrakiSayfaOpakCursorlaIstenir() async throws {
        try mock.stub("/feed", with: .success(Fixtures.data("feed_page")))
        let firstPage = try await api.fetchPage(cursor: nil, limit: nil)

        try mock.stub("/feed", with: .success(Fixtures.data("feed_page_last")))
        let lastPage = try await api.fetchPage(cursor: firstPage.nextCursor, limit: nil)

        #expect(lastPage.isLastPage)
        #expect(lastPage.items.count == 1)
        let endpoint = try #require(mock.receivedEndpoints.last as? FeedEndpoint)
        #expect(endpoint.query.contains(URLQueryItem(name: "cursor", value: "eyJvZmZzZXQiOiIxMCJ9")))
    }

    @Test func limitParametresiQueryDeTasinir() async throws {
        try mock.stub("/feed", with: .success(Fixtures.data("feed_page")))

        _ = try await api.fetchPage(cursor: nil, limit: 10)

        let endpoint = try #require(mock.receivedEndpoints.first as? FeedEndpoint)
        #expect(endpoint.query.contains(URLQueryItem(name: "limit", value: "10")))
    }

    /// İleri uyumluluk: bilinmeyen tipli item'lar sayfadan düşer, sayfa yine de akar (05 §2.12).
    @Test func bilinmeyenTipliItemlarFiltrelenir() async throws {
        try mock.stub("/feed", with: .success(Fixtures.data("feed_page_future")))

        let page = try await api.fetchPage(cursor: nil, limit: nil)

        #expect(page.items.count == 1)
        #expect(page.items.first?.id == "fi_901")
    }

    /// Feed endpoint'i tek denemedir; başarısızlık akışı kesmez, hata yüzeye çıkar (03 §8.3).
    @Test func feedEndpointiOtomatikRetryAlmaz() {
        let endpoint = FeedEndpoint(cursor: nil, limit: nil)

        #expect(endpoint.retryPolicy == .never)
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/feed")
    }

    @Test func tasimaHatasiAppErrorOlarakYuzeyeCikar() async throws {
        mock.stub("/feed", throwing: .network(.offline))

        await #expect(throws: AppError.network(.offline)) {
            _ = try await api.fetchPage(cursor: nil, limit: nil)
        }
    }

    /// Aynı bölüm feed'e iki kez düşerse `episode.id` üzerinden dedup (05 §2.12).
    @Test func dedupeYardimcisiAyniBolumuTekiller() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page").toDomain()
        let duplicated = page.items + page.items // fi_001, fi_002, fi_001, fi_002

        let deduped = duplicated.deduplicatingEpisodes()

        #expect(duplicated.count == 4)
        #expect(deduped.count == 2)
        #expect(deduped.map(\.id) == ["fi_001", "fi_002"])
    }

    /// 05 §2.12 dedup'u feed item `id`si düzeyinde DE ister: bölüm taşımayan item'lar
    /// (ör. `seriesPromo`) dahil, aynı item id ikinci kez düşerse tekillenir.
    @Test func dedupeYardimcisiAyniItemIdyiDeTekiller() throws {
        let series = try Fixtures.decode(SeriesWire.self, from: "series_detail").toDomain()
        let promo = FeedItem(id: "fi_promo01", type: .seriesPromo, episode: nil, series: series, progress: nil, reason: nil)

        let deduped = [promo, promo].deduplicatingEpisodes()

        #expect(deduped.count == 1)
        #expect(deduped.first?.id == "fi_promo01")
    }
}
