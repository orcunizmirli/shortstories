import Foundation

/// Taşıma katmanı arayüzü (03 §8.1'in tek normatif tanımı).
public protocol APIClientProtocol: Sendable {
    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response
}

/// URLSession tabanlı canlı istemci: istek kurulumu (header'lar) → interceptor zinciri →
/// validate (HTTP durum → `AppError` eşlemesi) → retry döngüsü → decode.
///
/// F0 kapsam notu (plan §5): auth interceptor / single-flight refresh (SS-021),
/// SPKI pinning (03 §8.4) ve cache policy uygulaması (SS-020) henüz YOKTUR;
/// `requiresAuth`/`cachePolicy` alanları sözleşme olarak taşınır.
public struct APIClient: APIClientProtocol {
    public let configuration: APIConfiguration
    let urlSession: URLSession
    /// Sıralı zincir: ör. [AuthInterceptor, LocaleInterceptor, ...] (F0'da boş).
    let interceptors: [any RequestInterceptor]
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(
        configuration: APIConfiguration,
        urlSession: URLSession = .shared,
        interceptors: [any RequestInterceptor] = []
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.interceptors = interceptors

        // Wire formatı camelCase'dir; anahtar dönüşümü YAPILMAZ (.useDefaultKeys — 05 kural 7).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        var attempt = 0
        while true {
            do {
                return try await performOnce(endpoint)
            } catch let error as AppError {
                // Yalnız idempotent istekler (GET ve idempotency-key taşıyanlar)
                // otomatik retry alır (03 §8.3).
                guard isIdempotent(endpoint),
                      let delay = endpoint.retryPolicy.delay(afterAttempt: attempt, error: error)
                else { throw error }
                attempt += 1
                try await Task.sleep(for: delay) // iptal edilirse retry döngüsü de biter
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

    private func performOnce<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        var request = try makeRequest(endpoint)
        do {
            for interceptor in interceptors {
                request = try await interceptor.adapt(request)
            }
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.unexpected(underlying: "Interceptor hatası: \(error)")
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

        try validate(response)

        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw AppError.network(.decoding)
        }
    }

    func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unexpected(underlying: "HTTP olmayan yanıt: \(type(of: response))")
        }
        switch http.statusCode {
        case 200 ..< 300:
            return
        case 401:
            // Retry değil; refresh akışı SS-021'de bağlanır (03 §8.2).
            throw AppError.auth(.sessionExpired)
        default:
            throw AppError.network(.server(status: http.statusCode))
        }
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
