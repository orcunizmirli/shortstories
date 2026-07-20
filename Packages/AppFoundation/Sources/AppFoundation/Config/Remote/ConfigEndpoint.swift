import Foundation

/// `GET /config` (05 §4.10). Config uçları AppFoundation-internal'dır: remote config
/// cross-cutting altyapıdır, bu yüzden istisnaen endpoint tanımı da burada yaşar (03 §8
/// kuralının bilinçli istisnası — auth uçlarıyla aynı gerekçe).
///
/// `requiresAuth == false`: config Splash'ta `POST /auth/guest` ile PARALEL çekilir
/// (05 §13.1) — ilk açılışta henüz token yoktur; ayrıca force-update kapısı
/// (`minSupportedVersion`) oturum olmadan da okunabilmelidir. Global config anonimdir;
/// deney atamaları client tarafında deterministik bucketing'e (AnalyticsKit) beslenir.
///
/// GET + `.default` retry → idempotent otomatik retry (03 §8.3). Cache uygulaması
/// `RemoteConfigClient`'ın kendi UserDefaults katmanındadır; `cachePolicy` alanı sözleşme
/// olarak `.networkOnly` kalır.
struct ConfigEndpoint: Endpoint {
    typealias Response = RemoteConfig

    var path: String {
        "/config"
    }

    var method: HTTPMethod {
        .get
    }

    var requiresAuth: Bool {
        false
    }
}
