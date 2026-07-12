import Foundation
import Testing
@testable import AppFoundation
import AppFoundationTestSupport

private struct TestPayload: Codable, Equatable, Sendable {
    let value: String
}

private struct GetTestEndpoint: Endpoint {
    typealias Response = TestPayload
    // Testleri hızlı tutmak için milisaniyelik backoff (jitter dahil deterministik sınırlı).
    var retry = RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1))
    var path: String { "/test" }
    var method: HTTPMethod { .get }
    var retryPolicy: RetryPolicy { retry }
}

private struct PostTestEndpoint: Endpoint {
    typealias Response = TestPayload
    var idempotency: String?
    var path: String { "/things" }
    var method: HTTPMethod { .post }
    var body: (any Encodable)? { TestPayload(value: "gonderilen") }
    var retryPolicy: RetryPolicy { RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1)) }
    var idempotencyKey: String? { idempotency }
}

/// URLProtocolStub statik durum taşıdığı için seri koşar.
@Suite(.serialized)
struct APIClientTests {
    private let client = APIClient(
        configuration: APIConfiguration(environment: .development,
                                        baseURL: URL(string: "https://api.test.local/v1")!),
        urlSession: URLProtocolStub.makeSession()
    )

    init() {
        URLProtocolStub.reset()
    }

    @Test func basariliYanitiDecodeEder() async throws {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 200),
             Data(#"{"value":"ok"}"#.utf8))
        }

        let response = try await client.send(GetTestEndpoint())

        #expect(response == TestPayload(value: "ok"))
        #expect(URLProtocolStub.receivedRequests.count == 1)
        #expect(URLProtocolStub.receivedRequests.first?.url?.absoluteString
                == "https://api.test.local/v1/test")
    }

    @Test func gecici500SonrasiRetryIleBasarir() async throws {
        URLProtocolStub.setHandler { request in
            // Handler, istek kaydedildikten sonra çağrılır: ilk istekte count == 1.
            if URLProtocolStub.receivedRequests.count < 2 {
                return (URLProtocolStub.httpResponse(for: request, status: 500), Data())
            }
            return (URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8))
        }

        let response = try await client.send(GetTestEndpoint())

        #expect(response == TestPayload(value: "ok"))
        #expect(URLProtocolStub.receivedRequests.count == 2)
    }

    @Test func kalici500RetryHakkiBitinceFirlatir() async {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 500), Data())
        }

        await #expect(throws: AppError.network(.server(status: 500))) {
            _ = try await client.send(GetTestEndpoint())
        }
        // 1 ilk deneme + 2 retry
        #expect(URLProtocolStub.receivedRequests.count == 3)
    }

    @Test func idempotentOlmayanPostRetryAlmaz() async {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 500), Data())
        }

        await #expect(throws: AppError.network(.server(status: 500))) {
            _ = try await client.send(PostTestEndpoint(idempotency: nil))
        }
        #expect(URLProtocolStub.receivedRequests.count == 1)
    }

    @Test func idempotencyKeyliPostRetryAlirVeHeaderTasir() async throws {
        URLProtocolStub.setHandler { request in
            if URLProtocolStub.receivedRequests.count < 2 {
                return (URLProtocolStub.httpResponse(for: request, status: 500), Data())
            }
            return (URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8))
        }

        let response = try await client.send(PostTestEndpoint(idempotency: "tx-123"))

        #expect(response == TestPayload(value: "ok"))
        #expect(URLProtocolStub.receivedRequests.count == 2)
        #expect(URLProtocolStub.receivedRequests.first?
            .value(forHTTPHeaderField: "Idempotency-Key") == "tx-123")
    }

    @Test func dortYuzBirSessionExpiredOlurRetryAlmaz() async {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 401), Data())
        }

        await #expect(throws: AppError.auth(.sessionExpired)) {
            _ = try await client.send(GetTestEndpoint())
        }
        #expect(URLProtocolStub.receivedRequests.count == 1)
    }

    @Test func dortYuzDortServerHatasiOlurRetryAlmaz() async {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 404), Data())
        }

        await #expect(throws: AppError.network(.server(status: 404))) {
            _ = try await client.send(GetTestEndpoint())
        }
        #expect(URLProtocolStub.receivedRequests.count == 1)
    }

    @Test func bozukJSONDecodingHatasinaEslenir() async {
        URLProtocolStub.setHandler { request in
            (URLProtocolStub.httpResponse(for: request, status: 200),
             Data("bu-json-degil".utf8))
        }

        await #expect(throws: AppError.network(.decoding)) {
            _ = try await client.send(GetTestEndpoint())
        }
    }

    @Test func baglantiHatasiOfflineOlarakEslenirVeRetryAlir() async {
        URLProtocolStub.setHandler { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: AppError.network(.offline)) {
            _ = try await client.send(GetTestEndpoint())
        }
        // offline retryable'dır: 1 ilk deneme + 2 retry
        #expect(URLProtocolStub.receivedRequests.count == 3)
    }
}
