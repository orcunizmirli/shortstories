import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

private struct TestPayload: Codable, Equatable {
    let value: String
}

private struct GetTestEndpoint: Endpoint {
    typealias Response = TestPayload
    // Testleri hızlı tutmak için milisaniyelik backoff (jitter dahil deterministik sınırlı).
    var retry = RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1))
    var path: String {
        "/test"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        retry
    }
}

private struct PostTestEndpoint: Endpoint {
    typealias Response = TestPayload
    var idempotency: String?
    var path: String {
        "/things"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        TestPayload(value: "gonderilen")
    }

    var retryPolicy: RetryPolicy {
        RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1))
    }

    var idempotencyKey: String? {
        idempotency
    }
}

/// Gövde-taşımayan uç (05 §4.2.1/§8: e-posta start/password, analitik batch → 204 No Content).
private struct EmptyBodyEndpoint: Endpoint {
    typealias Response = EmptyResponse
    var path: String {
        "/empty"
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

/// URLProtocolStub statik durum taşır: onu kullanan TÜM suite'ler bu kökün altına girer;
/// `.serialized` alt suite'lere özyinelemeli uygulanır ve çapraz kirlenmeyi önler.
@Suite(.serialized)
struct URLProtocolStubSerialTests {}

extension URLProtocolStubSerialTests {
    struct APIClientTests {
        private let client = APIClient(
            configuration: APIConfiguration(
                environment: .development,
                baseURL: URL(string: "https://api.test.local/v1")!
            ),
            urlSession: URLProtocolStub.makeSession()
        )

        init() {
            URLProtocolStub.reset()
        }

        @Test func basariliYanitiDecodeEder() async throws {
            URLProtocolStub.setHandler { request in
                (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
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
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
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
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
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
                (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data("bu-json-degil".utf8)
                )
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

        // MARK: - 204 / boş gövde decode kısa-devresi

        @Test func bosGovdeli204BasariDoner() async throws {
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 204), Data())
            }

            // Boş gövdeli 2xx: JSONDecoder'ın sahte "Unexpected end of file"i YERİNE başarı.
            let response = try await client.send(EmptyBodyEndpoint())

            #expect(response == EmptyResponse())
            #expect(URLProtocolStub.receivedRequests.count == 1)
        }

        @Test func bosGovdeli200DeBasariDoner() async throws {
            // 204 zorunlu değil: herhangi bir 2xx + boş gövde aynı kısa-devreye girer.
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 200), Data())
            }

            let response = try await client.send(EmptyBodyEndpoint())

            #expect(response == EmptyResponse())
        }

        @Test func bosGovdeAmaGovdeGerektirenTipDecodingHatasiVerir() async {
            // Boş gövde + gövde bekleyen tip: sahte EOF değil, tipli decoding hatası (sözleşme ihlali).
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 200), Data())
            }

            await #expect(throws: AppError.network(.decoding)) {
                _ = try await client.send(GetTestEndpoint())
            }
        }

        @Test func doluGovdeNormalDecodeDegismedi() async throws {
            // Regresyon: non-empty gövde davranışı aynen korunur (kısa-devre yalnız boş gövdede).
            URLProtocolStub.setHandler { request in
                (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await client.send(GetTestEndpoint())

            #expect(response == TestPayload(value: "ok"))
        }
    }
}
