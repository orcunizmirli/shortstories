/// Cursor sayfalama zarfının wire karşılığı: `{ items, nextCursor, ttlSec }` (05 §7.1).
/// Wire DTO'lar internal'dır — UI/ViewModel katmanı wire adı GÖRMEZ (05 kural 7);
/// erişim yalnız API istemcileri üzerinden domain tipleriyle olur.
struct PageWire<ItemWire: Decodable & Sendable>: Decodable, Sendable {
    let items: [ItemWire]
    let nextCursor: String?
    let ttlSec: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Present-but-invalid (zorunlu alanı bozuk) TEK bir item TÜM sayfayı düşürmesin (audit:
        // per-item resilience) — lossy eleman-bazlı decode, bozuk item atlanır, sayfanın kalanı akar.
        // (Sözleşme-geçerli ama render-dışı itemlar — .unknown tip — yine decode olur, mapping'de düşer.)
        items = try container.decodeLossyArray(ItemWire.self, forKey: .items)
        nextCursor = try container.decodeOpaqueCursor(forKey: .nextCursor) // boş "" → nil (sonsuz sayfalama önlenir)
        ttlSec = try container.decodeIfPresent(Int.self, forKey: .ttlSec)
    }

    private enum CodingKeys: String, CodingKey {
        case items, nextCursor, ttlSec
    }
}
