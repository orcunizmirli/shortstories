import Foundation

/// Auth uçları AppFoundation-internal'dır: oturum cross-cutting olduğu için istisnaen
/// endpoint tanımları da burada yaşar (03 §8 kuralının bilinçli istisnası; sözleşme 05 §4.2).
struct GuestAuthEndpoint: Endpoint {
    struct RequestBody: Encodable {
        let deviceId: String
        let platform: String
        let appVersion: String
        let locale: String
    }

    typealias Response = GuestAuthResponse

    let requestBody: RequestBody

    var path: String {
        "/auth/guest"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        requestBody
    }

    var requiresAuth: Bool {
        false
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `POST /auth/guest` yanıt zarfı (05 §4.2). `profile` alanı bilinçli decode edilmez —
/// UserProfile modeli feature sözleşmesidir; oturum yalnız kimlik + token'lara bakar.
struct GuestAuthResponse: Decodable, Sendable {
    let userId: String
    let accessToken: String
    let refreshToken: String
}

/// `POST /auth/refresh` (05 §4.2): access token süresi dolunca; yanıt rotasyonlu
/// yeni refresh token da taşır.
struct RefreshTokenEndpoint: Endpoint {
    struct RequestBody: Encodable {
        let refreshToken: String
    }

    struct Response: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
    }

    let requestBody: RequestBody

    var path: String {
        "/auth/refresh"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        requestBody
    }

    var requiresAuth: Bool {
        false
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}
