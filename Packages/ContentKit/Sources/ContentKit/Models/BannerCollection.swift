import Foundation

/// Kesfet hero banner'ı (05 §2.13). `deeplink`i Router (Coordinator) çözer.
public struct Banner: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Yatay hero görseli.
    public let imageURL: URL
    /// `shortseries://series/srs_x` veya https universal link.
    public let deeplink: URL
    public let title: String?
    public let startsAt: Date
    /// İstemci süresi geçmiş banner'ı göstermez (offline dahil, 05 §11).
    public let endsAt: Date

    public init(id: String, imageURL: URL, deeplink: URL, title: String?, startsAt: Date, endsAt: Date) {
        self.id = id
        self.imageURL = imageURL
        self.deeplink = deeplink
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    /// Gösterim penceresi kuralı: `startsAt` dahil, `endsAt` hariç. Cache'lenen banner
    /// süresi dolunca istemci gizler — gösterim kararı UI'da, kural burada.
    public func isActive(at date: Date = .now) -> Bool {
        startsAt <= date && date < endsAt
    }
}

/// Kesfet rafı (05 §2.13). Kanon rafları: Trend, Yeni, Top 10.
public struct Collection: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: Kind
    /// Lokalize raf başlığı.
    public let title: String
    /// Raf içeriği (ilk sayfa, max 20).
    public let seriesList: [Series]
    /// Raf "tümünü gör" sayfalaması (05 §7.1 cursor kalıbı).
    public let nextCursor: String?

    public enum Kind: String, Codable, Sendable, UnknownDecodable {
        case trending, new, top10, editorial, genre, unknown
    }

    public init(id: String, kind: Kind, title: String, seriesList: [Series], nextCursor: String?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.seriesList = seriesList
        self.nextCursor = nextCursor
    }
}

/// `GET /discover` yanıtının domain karşılığı: banner + koleksiyon rafları (05 §4.1 #9).
public struct DiscoverContent: Codable, Hashable, Sendable {
    public let banners: [Banner]
    public let collections: [Collection]

    public init(banners: [Banner], collections: [Collection]) {
        self.banners = banners
        self.collections = collections
    }
}
