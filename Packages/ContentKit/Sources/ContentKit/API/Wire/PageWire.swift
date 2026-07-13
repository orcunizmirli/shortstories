/// Cursor sayfalama zarfının wire karşılığı: `{ items, nextCursor, ttlSec }` (05 §7.1).
/// Wire DTO'lar internal'dır — UI/ViewModel katmanı wire adı GÖRMEZ (05 kural 7);
/// erişim yalnız API istemcileri üzerinden domain tipleriyle olur.
struct PageWire<ItemWire: Decodable & Sendable>: Decodable, Sendable {
    let items: [ItemWire]
    let nextCursor: String?
    let ttlSec: Int?
}
