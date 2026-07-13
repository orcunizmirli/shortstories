import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ContentKit

/// CatalogAPI davranış testleri — yalnız DOMAIN adları kullanılır (05 §12 kural 6).
struct CatalogAPITests {
    private let mock = MockAPIClient()
    private var api: CatalogAPI {
        CatalogAPI(client: mock)
    }

    @Test func diziDetayiIdIleIstenirVeDomainDoner() async throws {
        try mock.stub("/series/srs_77aa10", with: .success(Fixtures.data("series_detail")))

        let series = try await api.seriesDetail(id: SeriesID("srs_77aa10"))

        #expect(series.id == SeriesID("srs_77aa10"))
        #expect(series.releaseState == .completed)
        #expect(mock.receivedPaths == ["/series/srs_77aa10"])
    }

    @Test func bolumListesiCursorlaSayfalanir() async throws {
        try mock.stub("/series/srs_77aa10/episodes", with: .success(Fixtures.data("episodes_page")))

        let page = try await api.episodes(seriesId: SeriesID("srs_77aa10"), cursor: "abc123")

        #expect(page.items.count == 5)
        #expect(page.isLastPage)
        let endpoint = try #require(mock.receivedEndpoints.first as? EpisodeListEndpoint)
        #expect(endpoint.path == "/series/srs_77aa10/episodes")
        #expect(endpoint.query.contains(URLQueryItem(name: "cursor", value: "abc123")))
    }

    @Test func kesfetRaflariDomainOlarakDoner() async throws {
        try mock.stub("/discover", with: .success(Fixtures.data("discover")))

        let discover = try await api.discover()

        #expect(discover.banners.count == 1)
        #expect(discover.collections.map(\.kind) == [.trending, .top10])
        #expect(mock.receivedPaths == ["/discover"])
    }

    @Test func koleksiyonSayfasiSeriesListesiDoner() async throws {
        try mock.stub("/collections/col_top10", with: .success(Fixtures.data("collection_page")))

        let page = try await api.collectionPage(id: "col_top10", cursor: nil)

        #expect(page.items.count == 1)
        #expect(page.items.first?.id == SeriesID("srs_77aa10"))
        #expect(page.ttlSec == 600)
        #expect(mock.receivedPaths == ["/collections/col_top10"])
    }

    /// Katalog uçları cache sözleşmesi taşır (05 §7.2): detay/bölümler 300 sn,
    /// discover/koleksiyonlar stale-while-revalidate; feed networkOnly kalır.
    @Test func katalogEndpointleriCachePolitikasiBeyanEder() {
        #expect(SeriesDetailEndpoint(seriesId: SeriesID("s")).cachePolicy == .cacheFirst(ttl: .seconds(300)))
        #expect(EpisodeListEndpoint(seriesId: SeriesID("s"), cursor: nil).cachePolicy == .cacheFirst(ttl: .seconds(300)))
        #expect(DiscoverEndpoint().cachePolicy == .staleWhileRevalidate)
        #expect(CollectionPageEndpoint(collectionId: "c", cursor: nil).cachePolicy == .staleWhileRevalidate)
        #expect(FeedEndpoint(cursor: nil, limit: nil).cachePolicy == .networkOnly)
    }

    /// Sunucu ID'leri path'e ham interpolasyonla girmez: '/' ve boşluk gibi karakterler
    /// yüzde-kaçlanır ki ID tek bir path segmenti kalsın (path hiyerarşisi bozulmaz).
    @Test func pathSegmentleriYuzdeKaclanir() {
        #expect(SeriesDetailEndpoint(seriesId: SeriesID("srs/77 aa")).path == "/series/srs%2F77%20aa")
        #expect(
            EpisodeListEndpoint(seriesId: SeriesID("srs/77 aa"), cursor: nil).path
                == "/series/srs%2F77%20aa/episodes"
        )
        #expect(CollectionPageEndpoint(collectionId: "col/top 10", cursor: nil).path == "/collections/col%2Ftop%2010")
    }

    /// Boş ID'de davranış beyanı: precondition YOK — istek yine kurulur ve sunucu
    /// doğal 404 döner; istemci çökmez.
    @Test func bosIdIleIstekYineKurulur() {
        #expect(SeriesDetailEndpoint(seriesId: SeriesID("")).path == "/series/")
        #expect(EpisodeListEndpoint(seriesId: SeriesID(""), cursor: nil).path == "/series//episodes")
        #expect(CollectionPageEndpoint(collectionId: "", cursor: nil).path == "/collections/")
    }

    /// Süresi geçmiş banner gösterilmez (05 §2.13; offline dahil §11) — gösterim
    /// kararı UI'da, kural yardımcısı domain modelde.
    @Test func bannerAktiflikPenceresiDogruHesaplanir() async throws {
        try mock.stub("/discover", with: .success(Fixtures.data("discover")))
        let banner = try #require(try await api.discover().banners.first)

        #expect(!banner.isActive(at: isoDate("2026-06-30T23:59:59Z"))) // henüz başlamadı
        #expect(banner.isActive(at: isoDate("2026-07-12T00:00:00Z"))) // pencere içinde
        #expect(!banner.isActive(at: isoDate("2026-08-01T00:00:00Z"))) // endsAt dahil değil
    }
}
