import Foundation

/// `GET /discover` wire zarfı (05 §4.1 #9: banner + koleksiyonlar). 05'te örnek JSON
/// verilmemiştir; şema §2.13 model tanımlarından türetilmiştir ve backend contract
/// fixture setiyle F0 dondurmasında doğrulanır (05 §12 kural 6).
struct DiscoverWire: Decodable, Sendable {
    let banners: [BannerWire]
    let collections: [CollectionWire]

    /// Alan yok ya da `null` → boş liste (05 §12 kural 4 ruhu). AYRICA present-but-invalid bir eleman
    /// TÜM diziyi düşürmesin (audit MEDIUM): lossy eleman-bazlı decode → bozuk banner/koleksiyon atlanır,
    /// kalanı Keşfet'te görünür (bir bozuk backend elemanı tüm ekranı boşaltamaz).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        banners = try container.decodeLossyArray(BannerWire.self, forKey: .banners)
        collections = try container.decodeLossyArray(CollectionWire.self, forKey: .collections)
    }

    private enum CodingKeys: String, CodingKey {
        case banners, collections
    }

    func toDomain() -> DiscoverContent {
        DiscoverContent(
            banners: banners.map { $0.toDomain() },
            collections: collections.map { $0.toDomain() }
        )
    }
}

struct BannerWire: Decodable, Sendable {
    let id: String
    let imageURL: URL
    let deeplink: URL
    let title: String?
    let startsAt: Date
    let endsAt: Date

    func toDomain() -> Banner {
        Banner(id: id, imageURL: imageURL, deeplink: deeplink, title: title, startsAt: startsAt, endsAt: endsAt)
    }
}

struct CollectionWire: Decodable, Sendable {
    let id: String
    let kind: Collection.Kind
    let title: String
    let seriesList: [SeriesWire]
    let nextCursor: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Collection.Kind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        // Bozuk (present-but-invalid) bir series TÜM koleksiyonu düşürmesin (audit MEDIUM: nested
        // series izolasyonu) — lossy eleman-bazlı decode, bozuk series atlanır, kalan liste görünür.
        seriesList = try container.decodeLossyArray(SeriesWire.self, forKey: .seriesList)
        nextCursor = try container.decodeOpaqueCursor(forKey: .nextCursor) // boş "" → nil (sonsuz sayfalama önlenir)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, seriesList, nextCursor
    }

    func toDomain() -> Collection {
        Collection(
            id: id,
            kind: kind,
            title: title,
            seriesList: seriesList.map { $0.toDomain() },
            nextCursor: nextCursor
        )
    }
}
