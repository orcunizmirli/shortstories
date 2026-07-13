import Foundation

/// Taşıma katmanı arayüzü (03 §8.1'in tek normatif tanımı).
public protocol APIClientProtocol: Sendable {
    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response
}

/// URLSession tabanlı canlı istemci: istek kurulumu (header'lar) → interceptor zinciri →
/// validate (HTTP durum → `AppError` eşlemesi) → 401'de tek-uçuş refresh + BİR tekrar
/// (03 §8.2) → retry döngüsü → decode.
///
/// Kapsam notu: SPKI pinning (03 §8.4) ve cache policy uygulaması (SS-020) henüz YOKTUR;
/// `cachePolicy` alanı sözleşme olarak taşınır.
public struct APIClient: APIClientProtocol {
    public let configuration: APIConfiguration
    let urlSession: URLSession
    /// Sıralı zincir: ör. [AuthInterceptor, LocaleInterceptor, ...].
    let interceptors: [any RequestInterceptor]
    /// 401 kurtarma kolu (canlı: `TokenRefreshCoordinator`); nil ise 401 doğrudan yüzer.
    let tokenRefresher: (any AuthTokenRefreshing)?
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(
        configuration: APIConfiguration,
        urlSession: URLSession = .shared,
        interceptors: [any RequestInterceptor] = [],
        tokenRefresher: (any AuthTokenRefreshing)? = nil
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.interceptors = interceptors
        self.tokenRefresher = tokenRefresher

        // Tek kaynaklı wire kodlaması (05 §1 kural 7-8): camelCase aynen + fractional
        // saniye destekli ISO 8601 tarih stratejisi — bkz. JSONCoding.swift.
        decoder = .shortSeriesDefault()
        encoder = .shortSeriesDefault()
    }

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        var attempt = 0
        var hasRecoveredAuth = false
        var usedBearer: String?
        while true {
            do {
                return try await performOnce(endpoint, usedBearer: &usedBearer)
            } catch let error as AppError {
                // 401 (TOKEN_EXPIRED / kod yok) → tek-uçuş refresh → orijinal istek BİR KEZ
                // tekrar (03 §8.2). İkinci 401 refresh tetiklemez; refresh hatası olduğu gibi yüzer.
                let isRecoverable = error == .auth(.sessionExpired) && endpoint.requiresAuth && !hasRecoveredAuth
                if isRecoverable, let tokenRefresher {
                    try await tokenRefresher.refreshAccessToken(ifStaleTokenWas: usedBearer)
                    hasRecoveredAuth = true
                    continue
                }
                // Yalnız idempotent istekler (GET ve idempotency-key taşıyanlar)
                // otomatik retry alır (03 §8.3).
                guard isIdempotent(endpoint),
                      let delay = endpoint.retryPolicy.delay(afterAttempt: attempt, error: error)
                else { throw error }
                attempt += 1
                try await Task.sleep(for: delay) // iptal edilirse retry döngüsü de biter
            } catch is InvalidTokenSignal {
                // 401 + TOKEN_INVALID (05 §10.2): refresh DENENMEZ — Keychain temizliği +
                // misafir yeniden-bootstrap (SessionManager yolu), sonra orijinal istek
                // BİR KEZ tekrarlanır. Kurtarma yoksa tipli hata olarak yüzer.
                guard endpoint.requiresAuth, !hasRecoveredAuth, let tokenRefresher else {
                    throw AppError.auth(.sessionExpired)
                }
                try await tokenRefresher.recoverFromInvalidToken(ifStaleTokenWas: usedBearer)
                hasRecoveredAuth = true
            } catch let signal as RetryAfterSignal {
                // 429 + Retry-After (05 §10.2): retry hakkı varsa backoff YERİNE sunucunun
                // verdiği süre beklenir (üst sınır `maxRetryAfterDelay`).
                guard isIdempotent(endpoint),
                      endpoint.retryPolicy.delay(afterAttempt: attempt, error: signal.underlying) != nil
                else { throw signal.underlying }
                attempt += 1
                try await Task.sleep(for: signal.delay)
            }
        }
    }

    // MARK: - İstek kurulumu (test edilebilirlik için internal)

    func makeRequest(_ endpoint: some Endpoint) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw AppError.unexpected(underlying: "Geçersiz baseURL: \(configuration.baseURL)")
        }
        let path = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components.path += path
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let url = components.url else {
            throw AppError.unexpected(underlying: "URL kurulamadı: path=\(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let idempotencyKey = endpoint.idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw AppError.unexpected(underlying: "İstek gövdesi encode edilemedi: \(error)")
            }
        }
        return request
    }

    func isIdempotent(_ endpoint: some Endpoint) -> Bool {
        endpoint.method == .get || endpoint.idempotencyKey != nil
    }

    // MARK: - Tek deneme

    private func performOnce<E: Endpoint>(_ endpoint: E, usedBearer: inout String?) async throws -> E.Response {
        var request = try makeRequest(endpoint)
        let context = RequestContext(requiresAuth: endpoint.requiresAuth)
        do {
            for interceptor in interceptors {
                request = try await interceptor.adapt(request, context: context)
            }
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.unexpected(underlying: "Interceptor hatası: \(error)")
        }
        // Geç-401 yarışı için: bu denemenin kullandığı token, kurtarma çağrısına
        // bayat-token kontrolü olarak geçirilir (bkz. AuthTokenRefreshing).
        usedBearer = request.value(forHTTPHeaderField: "Authorization").map { header in
            header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw CancellationError()
            }
            throw Self.appError(from: urlError)
        } catch {
            throw AppError.unexpected(underlying: String(describing: error))
        }

        try validate(response, data: data)

        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw AppError.network(.decoding)
        }
    }

    // MARK: - HTTP durum + error.code → tipli hata (05 §10.2/10.3 sınır kuralı)

    func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unexpected(underlying: "HTTP olmayan yanıt: \(type(of: response))")
        }
        guard !(200 ..< 300).contains(http.statusCode) else {
            return
        }
        throw mapFailure(http: http, data: data)
    }

    /// Kural (05 §10.2): istemci ÖNCE `error.code`a, sonra HTTP koduna bakar; gövde
    /// yoksa/parse edilemezse HTTP sınıfının varsayılan davranışı uygulanır.
    private func mapFailure(http: HTTPURLResponse, data: Data) -> any Error {
        let code = (try? decoder.decode(APIErrorBody.self, from: data))?.error.code
        switch (http.statusCode, code) {
        case (401, "TOKEN_INVALID"):
            // Refresh DENENMEZ; `send` içindeki yeniden-bootstrap yoluna düşer.
            return InvalidTokenSignal()
        case (401, _):
            // TOKEN_EXPIRED ya da kod yok/bilinmiyor → tek-uçuş refresh + BİR tekrar (03 §8.2).
            return AppError.auth(.sessionExpired)
        case (403, "EPISODE_LOCKED"):
            return episodeLockedError(from: data)
        case (410, "SIGNED_URL_EXPIRED"):
            // Player katmanı `POST /playback/authorize` ile URL'i sessizce tazeler (05 §8.1).
            return AppError.playback(.signedURLExpired)
        case (429, _):
            if let delay = Self.retryAfterDelay(fromHeaderValue: http.value(forHTTPHeaderField: "Retry-After")) {
                return RetryAfterSignal(underlying: .network(.server(status: 429)), delay: delay)
            }
            return AppError.network(.server(status: 429))
        default:
            return AppError.network(.server(status: http.statusCode))
        }
    }

    private func episodeLockedError(from data: Data) -> AppError {
        guard let details = (try? decoder.decode(EpisodeLockedErrorEnvelope.self, from: data))?.error.details
        else {
            // `details` şarttır (UnlockSheet TEK istekle açılır — 05 §4.4); yoksa HTTP
            // sınıfının varsayılan davranışına dönülür.
            return .network(.server(status: 403))
        }
        return .content(.episodeLocked(details))
    }

    // MARK: - Retry-After (05 §10.2: "Retry-After header'ına uy")

    /// Header'dan okunan bekleme süresinin üst sınırı — sunucu ne derse desin 30 sn'den
    /// fazla beklenmez.
    static let maxRetryAfterDelay: Duration = .seconds(30)

    /// Saniye biçimli `Retry-After` değerini ayrıştırır (HTTP-date biçimi desteklenmez —
    /// ayrıştırılamayan değer `nil` döner ve normal backoff'a düşülür).
    static func retryAfterDelay(fromHeaderValue value: String?) -> Duration? {
        guard let value,
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return nil }
        return min(.seconds(seconds), maxRetryAfterDelay)
    }

    static func appError(from urlError: URLError) -> AppError {
        switch urlError.code {
        case .timedOut:
            .network(.timeout)
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed:
            .network(.offline)
        default:
            .unexpected(underlying: "URLError(\(urlError.code.rawValue))")
        }
    }
}

/// 403 `EPISODE_LOCKED` gövdesinden yalnız `error.details`i tipli okuyan dar zarf.
private struct EpisodeLockedErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable {
        let details: EpisodeLockDetails?
    }

    let error: ErrorPayload
}

// MARK: - send-içi eşleme sinyalleri (katman sınırından GEÇMEZ — 03 §10.1 kuralı bozulmaz)

/// 401 + `TOKEN_INVALID` (05 §10.2): refresh yerine Keychain temizliği + misafir
/// yeniden-bootstrap gerekir. Kurtarma tükenirse `AppError.auth(.sessionExpired)` olarak
/// yüzer; feature'lar bu tipi asla görmez.
struct InvalidTokenSignal: Error {}

/// 429 + `Retry-After` header'ı (05 §10.2): backoff yerine sunucunun verdiği (üst sınırlı)
/// süre beklenir. Retry hakkı yoksa `underlying` yüzer.
struct RetryAfterSignal: Error {
    let underlying: AppError
    let delay: Duration
}
