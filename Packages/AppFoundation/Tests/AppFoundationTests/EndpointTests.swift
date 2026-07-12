import Foundation
import Testing
@testable import AppFoundation

private struct EmptyResponse: Decodable {}

private struct MinimalEndpoint: Endpoint {
    typealias Response = EmptyResponse
    var path: String {
        "/minimal"
    }

    var method: HTTPMethod {
        .get
    }
}

private struct FeedLikeEndpoint: Endpoint {
    typealias Response = EmptyResponse
    let cursor: String?
    var path: String {
        "/feed"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
    }
}

private struct UnlockLikeEndpoint: Endpoint {
    typealias Response = EmptyResponse
    var path: String {
        "episodes/unlock"
    } // baş slash'sız — normalize edilmeli
    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        ["episodeID": "e1"]
    }

    var retryPolicy: RetryPolicy {
        .never
    }

    var idempotencyKey: String? {
        "tx-1"
    }
}

private struct PlainPostEndpoint: Endpoint {
    typealias Response = EmptyResponse
    var path: String {
        "/things"
    }

    var method: HTTPMethod {
        .post
    }
}

struct EndpointTests {
    private let client = APIClient(
        configuration: APIConfiguration(
            environment: .development,
            baseURL: URL(string: "https://api.test.local/v1")!
        )
    )

    @Test func protokolVarsayilanlari() {
        let endpoint = MinimalEndpoint()
        #expect(endpoint.requiresAuth == true)
        #expect(endpoint.retryPolicy == .default)
        #expect(endpoint.idempotencyKey == nil)
        #expect(endpoint.cachePolicy == .networkOnly)
        #expect(endpoint.query.isEmpty)
        #expect(endpoint.body == nil)
    }

    @Test func urlKurulumuVersiyonOnekiniBaseURLdenAlir() throws {
        // Versiyon öneki (/v1) baseURL'in sahipliğindedir, path'e YAZILMAZ (03 §8.1).
        let request = try client.makeRequest(FeedLikeEndpoint(cursor: "abc"))
        #expect(request.url?.absoluteString == "https://api.test.local/v1/feed?cursor=abc")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func bosQueryUrlYeSorguEklemez() throws {
        let request = try client.makeRequest(FeedLikeEndpoint(cursor: nil))
        #expect(request.url?.absoluteString == "https://api.test.local/v1/feed")
    }

    @Test func basSlashsizPathNormalizeEdilir() throws {
        let request = try client.makeRequest(UnlockLikeEndpoint())
        #expect(request.url?.absoluteString == "https://api.test.local/v1/episodes/unlock")
    }

    @Test func postGovdesiVeHeaderlarKurulur() throws {
        let request = try client.makeRequest(UnlockLikeEndpoint())
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "tx-1")

        let bodyData = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode([String: String].self, from: bodyData)
        #expect(decoded == ["episodeID": "e1"])
    }

    @Test func govdesizGetContentTypeTasimaz() throws {
        let request = try client.makeRequest(MinimalEndpoint())
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
    }

    @Test func idempotencyTespiti() {
        // GET ve idempotency-key taşıyan istekler idempotenttir (03 §8.3).
        #expect(client.isIdempotent(MinimalEndpoint()))
        #expect(client.isIdempotent(UnlockLikeEndpoint()))
        #expect(!client.isIdempotent(PlainPostEndpoint()))
    }
}
