import AppFoundation

/// For You feed servisi (SS-032). PlayerFeed (Ana Sayfa) beslemesi; Splash ilk isteği
/// arka planda başlatır (05 §4.3). Tüketiciler protokole bağlanır (test için mock'lanabilir).
public protocol FeedServicing: Sendable {
    /// `GET /feed` — cursor sayfalama (05 §7.1). `cursor: nil` = ilk sayfa; sonraki
    /// sayfalar bir önceki yanıtın OPAK `nextCursor`ıyla istenir. `limit: nil` =
    /// sunucu varsayılanı (feed 10; sunucu 50 ile sınırlar).
    func fetchPage(cursor: String?, limit: Int?) async throws -> Page<FeedItem>
}

/// Canlı implementasyon: wire decode `APIClientProtocol`ün decoder'ında, wire→domain
/// eşleme burada — UI katmanına yalnız domain tipleri çıkar (05 kural 7).
public struct FeedAPI: FeedServicing {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func fetchPage(cursor: String?, limit: Int?) async throws -> Page<FeedItem> {
        try await client.send(FeedEndpoint(cursor: cursor, limit: limit)).toDomain()
    }
}
