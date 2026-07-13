/// Cursor tabanlı sayfalama zarfının domain karşılığı (05 §7.1):
/// `{ items, nextCursor, ttlSec }`. Tüm listeler aynı zarfı kullanır; offset tabanlı
/// sayfalama HİÇBİR endpoint'te yoktur.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    /// Opak, URL-safe base64 cursor; istemci içeriğini YORUMLAMAZ, aynen geri gönderir.
    /// nil = son sayfa.
    public let nextCursor: String?
    /// Yanıt gövdesi tazelik süresi (ör. feed 300 sn); zarfın opsiyonel alanıdır.
    public let ttlSec: Int?
    /// Wire→domain eşlemede güvenle DÜŞÜRÜLEN item sayısı (bilinmeyen tip, eksik zorunlu
    /// yük — 05 §2.12). Düşürme sessiz kayıp olmasın diye yüzeye çıkar; telemetri/log tüketir.
    public let droppedItemCount: Int

    public init(items: [Item], nextCursor: String?, ttlSec: Int?, droppedItemCount: Int = 0) {
        self.items = items
        self.nextCursor = nextCursor
        self.ttlSec = ttlSec
        self.droppedItemCount = droppedItemCount
    }

    /// `nextCursor: null` → son sayfa. Boş `items` + nil cursor geçerli "boş liste"dir.
    public var isLastPage: Bool {
        nextCursor == nil
    }
}

extension Page: Equatable where Item: Equatable {}
extension Page: Hashable where Item: Hashable {}
