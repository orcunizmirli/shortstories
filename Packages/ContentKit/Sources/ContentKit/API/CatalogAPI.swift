import AppFoundation

/// Katalog servisi (SS-031): dizi detayı, bölüm listesi, Kesfet rafları,
/// koleksiyon sayfalaması. Tüketiciler (DiscoverKit, PlayerKit, LibraryKit — 03 §4 R3)
/// protokole bağlanır; DI init-injection ile kurulur.
public protocol CatalogServicing: Sendable {
    /// `GET /series/{id}` — DiziDetay.
    func seriesDetail(id: SeriesID) async throws -> Series

    /// `GET /series/{id}/episodes?cursor=` — BolumListesi/DiziDetay ızgarası.
    /// Dönen `access` alanları UI ön-gösterimidir; oynatma yetkisini authorize çözer.
    func episodes(seriesId: SeriesID, cursor: String?) async throws -> Page<Episode>

    /// `GET /discover` — Kesfet banner + koleksiyon rafları.
    func discover() async throws -> DiscoverContent

    /// `GET /collections/{id}?cursor=` — raf "tümünü gör" sayfalaması.
    func collectionPage(id: String, cursor: String?) async throws -> Page<Series>
}

public struct CatalogAPI: CatalogServicing {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func seriesDetail(id: SeriesID) async throws -> Series {
        try await client.send(SeriesDetailEndpoint(seriesId: id)).toDomain()
    }

    public func episodes(seriesId: SeriesID, cursor: String?) async throws -> Page<Episode> {
        try await client.send(EpisodeListEndpoint(seriesId: seriesId, cursor: cursor)).toDomain()
    }

    public func discover() async throws -> DiscoverContent {
        try await client.send(DiscoverEndpoint()).toDomain()
    }

    public func collectionPage(id: String, cursor: String?) async throws -> Page<Series> {
        try await client.send(CollectionPageEndpoint(collectionId: id, cursor: cursor)).toDomain()
    }
}
