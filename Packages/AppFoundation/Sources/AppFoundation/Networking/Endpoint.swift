import Foundation

/// İstemci cache stratejisi (03 §8.1). F0'da yalnız `.networkOnly` uygulanır;
/// cache katmanı SS-020+ kapsamındadır — alan sözleşme olarak taşınır.
public enum APICachePolicy: Sendable, Equatable {
    case networkOnly
    case cacheFirst(ttl: Duration)
    case staleWhileRevalidate
}

/// İstemci networking arayüzünün tek normatif `Endpoint` tanımı (03 §8.1).
/// Endpoint TANIMLARI feature paketlerinde yaşar; taşıma katmanı (`APIClient`)
/// AppFoundation'dadır.
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    /// Versiyon öneki İÇERMEZ — `/v1` baseURL'in sahipliğindedir (ör. "/feed").
    var path: String { get }
    var method: HTTPMethod { get }
    var query: [URLQueryItem] { get }
    var body: (any Encodable)? { get }
    /// Varsayılan: true. F0'da auth interceptor yoktur (SS-021); alan sözleşme için tanımlıdır.
    var requiresAuth: Bool { get }
    /// Varsayılan: .default
    var retryPolicy: RetryPolicy { get }
    /// Varsayılan: nil (header eklenmez). Değer varsa `Idempotency-Key` header'ı olarak
    /// gönderilir ve isteği otomatik retry için idempotent kılar (03 §8.3).
    var idempotencyKey: String? { get }
    /// Varsayılan: .networkOnly
    var cachePolicy: APICachePolicy { get }
}

public extension Endpoint {
    var query: [URLQueryItem] { [] }
    var body: (any Encodable)? { nil }
    var requiresAuth: Bool { true }
    var retryPolicy: RetryPolicy { .default }
    var idempotencyKey: String? { nil }
    var cachePolicy: APICachePolicy { .networkOnly }
}
