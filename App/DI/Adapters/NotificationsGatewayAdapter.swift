import AppFoundation
import DiscoverKit
import Foundation
import ProfileKit

// ProfileKit `NotificationsGateway`'in canlı adaptörü (SS-144; NTF-04, 05 §13 TASLAK
// `GET /notifications?cursor=`). Port ProfileKit'te tanımlı (tüketici); App onu AppFoundation
// `APIClientProtocol`üne (üretici) köprüler. Endpoint TANIMLARI kompozisyon kökündedir (03 §8.1:
// Endpoint tanımları feature/uygulama sınırında yaşar) — ProfileKit yalnız protokolü + domain
// tiplerini görür. Auth interceptor + `URLError → AppError.network(.offline)` eşlemesi APIClient
// katmanındadır; adaptör hataları AYNEN iletir (model banner'a çevirir).
//
// TODO(SS-144 endpoint): 05 §13 uçları TASLAK. Path/DTO makul varsayıldı; endpoint kesinleşince
// path'ler (`/notifications`, `/notifications/read`, `/notifications/read-all`,
// `/notifications/{id}`) + istek gövdesi anahtarları (`ids`) sözleşmeyle sabitlenir.

// MARK: - Canlı gateway

/// ProfileKit `NotificationsGateway` → `APIClient`. Coin/hesap MUTASYONU taşımaz — yalnız bildirim
/// listesi okuma + okundu/sil durum mutasyonu (port sözleşmesi).
struct APINotificationsGateway: NotificationsGateway {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetch(cursor: String?) async throws -> NotificationsPage {
        let wire = try await client.send(NotificationsFetchEndpoint(cursor: cursor))
        // Bozuk sunucu son sayfayı `nextCursor: ""` (null yerine) döndürebilir. Boş/whitespace cursor'u
        // `nil`'e normalize et (kardeş adaptör `!isEmpty` konvansiyonu, LibraryCatalogAdapter/PlaybackFeedSeed):
        // aksi halde `isLastPage` false kalıp scroll-to-bottom sayfa-1'i sonsuz yeniden çeker (SS-144 R2).
        let hasCursor = wire.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return NotificationsPage(items: wire.items, nextCursor: hasCursor ? wire.nextCursor : nil)
    }

    func markRead(ids: [NotificationID]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await client.send(NotificationsMarkReadEndpoint(ids: ids))
    }

    func markAllRead() async throws {
        _ = try await client.send(NotificationsMarkAllReadEndpoint())
    }

    func delete(id: NotificationID) async throws {
        _ = try await client.send(NotificationDeleteEndpoint(id: id))
    }
}

// MARK: - Endpoint'ler (05 §13 TASLAK)

/// `GET /notifications?cursor=` — cursor'suz ilk sayfa, cursor'lu sonraki (05 §7.1 zarf). GET →
/// idempotent, APIClient varsayılan retry politikasını uygular. `cursor` opak ve URL-safe'tir; boş/nil
/// ise ilk sayfa istenir.
private struct NotificationsFetchEndpoint: Endpoint {
    typealias Response = NotificationsListWire

    let cursor: String?

    var path: String {
        "/notifications"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        guard let cursor, !cursor.isEmpty else { return [] }
        return [URLQueryItem(name: "cursor", value: cursor)]
    }
}

/// `POST /notifications/read` — verilen kimlikleri okundu işaretle (satır okundu / tap sonrası).
/// Otomatik-retry YOK: okundu mutasyonu telafisi `NotificationCenterModel`'de (optimistik + geri alma).
private struct NotificationsMarkReadEndpoint: Endpoint {
    typealias Response = EmptyResponse

    struct RequestBody: Encodable, Sendable {
        let ids: [String]
    }

    let ids: [NotificationID]

    var path: String {
        "/notifications/read"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(ids: ids.map(\.rawValue))
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `POST /notifications/read-all` — tümünü okundu işaretle ("tümünü okundu say", 02 §4.15). Gövdesiz.
private struct NotificationsMarkAllReadEndpoint: Endpoint {
    typealias Response = EmptyResponse

    var path: String {
        "/notifications/read-all"
    }

    var method: HTTPMethod {
        .post
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `DELETE /notifications/{id}` — tek bildirimi sil (sola-kaydır → sil, 02 §4.15). Idempotent; telafi
/// (silinen öğeyi geri ekleme) modeldedir.
private struct NotificationDeleteEndpoint: Endpoint {
    typealias Response = EmptyResponse

    let id: NotificationID

    var path: String {
        "/notifications/\(id.rawValue.pathSegmentEscaped)"
    }

    var method: HTTPMethod {
        .delete
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

// MARK: - Wire

/// `GET /notifications?cursor=` yanıt zarfı (05 §7.1 cursor kalıbı: `{ items, nextCursor }`).
/// `AppNotification` zaten wire `camelCase` ile `Decodable`dır (ProfileKit domain tipi = wire tipi,
/// 05 §1.7 `useDefaultKeys`); zarf yalnız listeyi + opak cursor'u sarar. `nextCursor: null` → son sayfa.
/// Testin sözleşme örneğini decode edebilmesi için modül-içi (private değil).
struct NotificationsListWire: Decodable, Sendable {
    let items: [AppNotification]
    let nextCursor: String?
}

// MARK: - Model fabrikası (AppComposition eklentisi — dosya uzunluğu için burada)

extension AppComposition {
    /// BildirimMerkezi modeli (SS-144; NTF-04, 02 §4.15) — canlı `NotificationsGateway` (05 §13 taslak)
    /// + `ab_variants` dekoratörlü analitik. `delegate` = ProfileCoordinator (rota köprüsü + `Kesfet`
    /// fallback App'te, R2). Coin/hesap mutasyonu taşımaz. Diğer model fabrikaları `AppComposition`'da;
    /// bu, dosya-uzunluğu sınırından ötürü bildirim wiring'iyle aynı yerde tutulur.
    func makeNotificationCenterModel(delegate: (any NotificationCenterDelegate)?) -> NotificationCenterModel {
        NotificationCenterModel(
            gateway: APINotificationsGateway(client: dependencies.apiClient),
            analytics: decoratedAnalytics,
            delegate: delegate
        )
    }
}

// MARK: - App feature flag (03 §11 tipli flag kalıbı)

/// ProfileKit BildirimMerkezi görünürlük flag'i (SS-144). Varsayılan KODDADIR: config gelmezse
/// KAPALI (F1 varsayılanı) — Profil'de "Bildirimler" satırı gizli, deep-link/push yine Profil'e
/// düşer (ekran flag'ten bağımsız çalışır). Remote config açınca satır görünür + ekran push edilir.
enum ProfileFlags {
    static let notificationCenterEnabled = FlagKey(name: "profile.notification_center_enabled", default: false)
}

// MARK: - Bildirim rota köprüsü (ham String → DeepLinkRoute) — izole test edilir

/// BildirimMerkezi satır rotasını (ham deep-link String, ProfileKit R2 gereği Route enum'unu görmez)
/// App `DeepLinkRoute`'una köprüler (02 §8.4). Push ile AYNI çözüm: `URL(string:)` + `DeepLinkRoute(url:)`;
/// URL'e çevrilemeyen / bilinmeyen path / biçimsiz ID → nil (App `Kesfet` fallback'ini uygular, §8.4).
/// Saf/durumsuz → kompozisyonsuz test edilir (deliverable testleri).
enum NotificationRouteBridge {
    static func route(from rawRoute: String) -> DeepLinkRoute? {
        let trimmed = rawRoute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return DeepLinkRoute(url: url)
    }
}
