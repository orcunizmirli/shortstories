import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

private struct Payload: Codable, Equatable {
    let value: String
}

private struct AuthedEndpoint: Endpoint {
    typealias Response = Payload
    var path: String {
        "/feed"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1))
    }
}

private struct PublicEndpoint: Endpoint {
    typealias Response = Payload
    var path: String {
        "/auth/guest"
    }

    var method: HTTPMethod {
        .post
    }

    var requiresAuth: Bool {
        false
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

private final class SpyTokenRefresher: AuthTokenRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var invalidTokenCalls = 0
    private var result: Result<String, AppError> = .success("at_new")

    var callCount: Int {
        lock.withLock { calls }
    }

    var invalidTokenRecoveryCallCount: Int {
        lock.withLock { invalidTokenCalls }
    }

    func stub(_ newResult: Result<String, AppError>) {
        lock.withLock { result = newResult }
    }

    func refreshAccessToken(ifStaleTokenWas _: String?) async throws -> String {
        let current = lock.withLock {
            calls += 1
            return result
        }
        return try current.get()
    }

    func recoverFromInvalidToken(ifStaleTokenWas _: String?) async throws -> String {
        let current = lock.withLock {
            invalidTokenCalls += 1
            return result
        }
        return try current.get()
    }
}

/// URLProtocolStub statik durum taşıdığı için `URLProtocolStubSerialTests` kökü altında seri koşar.
extension URLProtocolStubSerialTests {
    struct APIClientAuthRecoveryTests {
        private let refresher = SpyTokenRefresher()
        private let client: APIClient

        init() {
            URLProtocolStub.reset()
            client = APIClient(
                configuration: APIConfiguration(
                    environment: .development,
                    baseURL: URL(string: "https://api.test.local/v1")!
                ),
                urlSession: URLProtocolStub.makeSession(),
                tokenRefresher: refresher
            )
        }

        @Test func dortYuzBirSonrasiRefreshEdipIstegiBirKezTekrarlar() async throws {
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 2 {
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                }
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await client.send(AuthedEndpoint())

            #expect(response == Payload(value: "ok"))
            #expect(URLProtocolStub.receivedRequests.count == 2)
            #expect(refresher.callCount == 1)
        }

        @Test func kurtarmaSonrasiRetryTazeTokeniGonderirBayatDegil() async throws {
            // audit LOW (self-review): refresh TAZE access döndürür ama keychain access-yazımı best-effort
            // koparsa interceptor BAYAT token okur; send() dönen tazeyi ATIP re-read'e güvenirse retry bayat
            // gönderip 2. 401 → gereksiz sessionExpired. Fix: dönen taze token retry'da override edilir.
            let store = MockSecureStore()
            try store.setString("at_old", forKey: .accessToken) // keychain BAYAT (yazım koptu, refresh güncellemedi)
            let localRefresher = SpyTokenRefresher()
            localRefresher.stub(.success("at_new")) // refresh tazeyi döndürür ama store'u GÜNCELLEMEZ
            let authedClient = try APIClient(
                configuration: APIConfiguration(
                    environment: .development,
                    baseURL: #require(URL(string: "https://api.test.local/v1"))
                ),
                urlSession: URLProtocolStub.makeSession(),
                interceptors: [AuthInterceptor(secureStore: store)],
                tokenRefresher: localRefresher
            )
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 1 {
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data()) // 1. istek (bayat) → 401
                }
                // 2. istek TAZE token taşımalı (override); bayatsa 401 kalır → send sessionExpired atardı.
                let ok = request.value(forHTTPHeaderField: "Authorization") == "Bearer at_new"
                return (
                    URLProtocolStub.httpResponse(for: request, status: ok ? 200 : 401),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await authedClient.send(AuthedEndpoint())

            #expect(response == Payload(value: "ok")) // taze token gönderildi → 200 (bayat olsaydı sessionExpired)
            #expect(URLProtocolStub.receivedRequests.count == 2)
            #expect(localRefresher.callCount == 1)
        }

        @Test func overrideOneShotSonraki429RetrysindeBayatTasinmaz() async throws {
            // self-review (#3d): override YALNIZ kurtarmayı izleyen İLK denemede kullanılmalı; 429/idempotent-retry
            // döngüsünde TAŞINMAMALI (backoff sırasında eşzamanlı rotasyon → bayat override → gereksiz sessionExpired).
            // Senaryo: kurtarma at_v1 döndürür (o an keychain'e yazılmamış); backoff'ta keychain at_v2'ye rotasyonlanır;
            // 3. istek at_v1'i DEĞİL keychain'deki taze at_v2'yi taşımalı (one-shot temizler).
            let store = MockSecureStore()
            try store.setString("at_v2", forKey: .accessToken) // interceptor'ın okuduğu TAZE token
            let localRefresher = SpyTokenRefresher()
            localRefresher.stub(.success("at_v1")) // kurtarmanın döndürdüğü (backoff'ta bayatlayan) token
            let authedClient = try APIClient(
                configuration: APIConfiguration(
                    environment: .development,
                    baseURL: #require(URL(string: "https://api.test.local/v1"))
                ),
                urlSession: URLProtocolStub.makeSession(),
                interceptors: [AuthInterceptor(secureStore: store)],
                tokenRefresher: localRefresher
            )
            // receivedRequests.count 1-indexli (mevcut istek dahil sayılır).
            URLProtocolStub.setHandler { request in
                switch URLProtocolStub.receivedRequests.count {
                case 1:
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data()) // 1. istek → 401 → refresh
                case 2:
                    // 2. istek override at_v1 taşır → 429 (backoff); one-shot override'ı temizlemeli.
                    return (URLProtocolStub.httpResponse(for: request, status: 429, headers: ["Retry-After": "0"]), Data())
                default:
                    // 3. istek: override TEMİZLENDİĞİ için interceptor'ın taze at_v2'si gitmeli (at_v1 DEĞİL).
                    let fresh = request.value(forHTTPHeaderField: "Authorization") == "Bearer at_v2"
                    return (
                        URLProtocolStub.httpResponse(for: request, status: fresh ? 200 : 401),
                        Data(#"{"value":"ok"}"#.utf8)
                    )
                }
            }

            let response = try await authedClient.send(AuthedEndpoint())

            #expect(response == Payload(value: "ok")) // 3. istek taze at_v2 taşıdı (bayat at_v1 taşınmadı)
            #expect(URLProtocolStub.receivedRequests.count == 3)
        }

        @Test func refreshSonrasiTekrarDa401IseSessionExpiredFirlarVeIkinciRefreshYapilmaz() async {
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 401), Data())
            }

            await #expect(throws: AppError.auth(.sessionExpired)) {
                _ = try await client.send(AuthedEndpoint())
            }
            #expect(URLProtocolStub.receivedRequests.count == 2)
            #expect(refresher.callCount == 1)
        }

        @Test func requiresAuthOlmayanUcta401RefreshTetiklemez() async {
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 401), Data())
            }

            await #expect(throws: AppError.auth(.sessionExpired)) {
                _ = try await client.send(PublicEndpoint())
            }
            #expect(URLProtocolStub.receivedRequests.count == 1)
            #expect(refresher.callCount == 0)
        }

        @Test func refreshBasarisizsaHataYuzerVeTekrarYapilmaz() async {
            refresher.stub(.failure(.auth(.sessionExpired)))
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 401), Data())
            }

            await #expect(throws: AppError.auth(.sessionExpired)) {
                _ = try await client.send(AuthedEndpoint())
            }
            #expect(URLProtocolStub.receivedRequests.count == 1)
            #expect(refresher.callCount == 1)
        }

        // MARK: - 401 error.code ayrımı (05 §10.2)

        @Test func tokenExpiredKodlu401RefreshAkisiniKullanir() async throws {
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 2 {
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 401),
                        Data(#"{"error":{"code":"TOKEN_EXPIRED","message":"Token süresi doldu."},"requestId":"req_1"}"#
                            .utf8)
                    )
                }
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await client.send(AuthedEndpoint())

            #expect(response == Payload(value: "ok"))
            #expect(refresher.callCount == 1)
            #expect(refresher.invalidTokenRecoveryCallCount == 0)
            #expect(URLProtocolStub.receivedRequests.count == 2)
        }

        @Test func tokenInvalidKodlu401RefreshDenemedenYenidenBootstrapYolunaGider() async throws {
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 2 {
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 401),
                        Data(#"{"error":{"code":"TOKEN_INVALID","message":"Token geçersiz."},"requestId":"req_1"}"#
                            .utf8)
                    )
                }
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await client.send(AuthedEndpoint())

            #expect(response == Payload(value: "ok"))
            // Refresh DENENMEZ; Keychain temizliği + misafir yeniden-bootstrap yolu çağrılır.
            #expect(refresher.callCount == 0)
            #expect(refresher.invalidTokenRecoveryCallCount == 1)
            // Orijinal istek BİR kez tekrarlanır.
            #expect(URLProtocolStub.receivedRequests.count == 2)
        }

        @Test func refreshDisindakiHatalarRefreshTetiklemez() async {
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 404), Data())
            }

            await #expect(throws: AppError.network(.server(status: 404))) {
                _ = try await client.send(AuthedEndpoint())
            }
            #expect(refresher.callCount == 0)
        }
    }
}
