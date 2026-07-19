/// Cursor sayfalama zarfının BildirimMerkezi karşılığı (05 §7.1 `{ items, nextCursor }`).
/// ContentKit `Page`'i MİMİKLER (ProfileKit ContentKit'i import etmez — R2); opak `nextCursor`
/// istemcide yorumlanmaz, aynen geri gönderilir. Tüm listeler aynı cursor kalıbını kullanır,
/// offset sayfalama YOKTUR. `nextCursor == nil` = son sayfa; boş `items` + nil cursor = geçerli
/// "boş liste" (BildirimMerkezi boş durumu).
public struct NotificationsPage: Sendable, Equatable {
    public let items: [AppNotification]
    public let nextCursor: String?

    public init(items: [AppNotification], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    /// `nextCursor: null` → son sayfa (View footer spinner'ını durdurur).
    public var isLastPage: Bool {
        nextCursor == nil
    }
}

/// BildirimMerkezi ağ portu (NTF-04; 05 §13 TASLAK `GET /notifications?cursor=`). `Sendable` port —
/// canlı implementasyon (Endpoint + `APIClientProtocol`) App/altyapı katmanında wire edilir; taslak
/// endpoint kesinleşince bağlanır (TODO SS-144 App wiring). ProfileKit yalnız bu protokolü ve domain
/// tiplerini görür (03 §8.1: Endpoint tanımları feature/uygulama sınırında yaşar).
///
/// Model bu portu enjekte alır (fake/mock ile izole test edilir, deliverable 4). Coin/hesap
/// MUTASYONU taşımaz — yalnız bildirim listesi okuma + okundu/sil durum mutasyonu.
public protocol NotificationsGateway: Sendable {
    /// `GET /notifications?cursor=` — cursor'suz ilk sayfa, cursor'lu sonraki. Zarf 05 §7.1
    /// `{ items, nextCursor }`. Ağ yoksa `AppError.network(.offline)` fırlatır (model banner'a çevirir).
    func fetch(cursor: String?) async throws -> NotificationsPage

    /// Verilen bildirimleri okundu işaretle (satır okundu / tap sonrası). Taslak `POST /notifications/read`.
    func markRead(ids: [NotificationID]) async throws

    /// Tümünü okundu işaretle ("tümünü okundu say", 02 §4.15 üst aksiyon). Taslak `POST /notifications/read-all`.
    func markAllRead() async throws

    /// Tek bildirimi sil (sola-kaydır → sil, 02 §4.15). Taslak `DELETE /notifications/{id}`.
    func delete(id: NotificationID) async throws
}
