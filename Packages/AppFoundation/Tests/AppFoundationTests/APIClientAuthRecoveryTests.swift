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
