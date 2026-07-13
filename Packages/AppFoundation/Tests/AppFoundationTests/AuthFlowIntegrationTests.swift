import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

private struct FeedPayload: Codable, Equatable {
    let value: String
}

private struct FeedEndpoint: Endpoint {
    typealias Response = FeedPayload
    var path: String {
        "/feed"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// SS-021 + SS-022 uçtan uca: AuthInterceptor + TokenRefreshCoordinator + APIClient
/// (+ SessionManager düşüş akışı) URLProtocolStub üzerinde birlikte doğrulanır.
extension URLProtocolStubSerialTests {
    @MainActor
    struct AuthFlowIntegrationTests {
        private let secureStore = MockSecureStore()
        private let configuration = APIConfiguration(
            environment: .development,
            baseURL: URL(string: "https://api.test.local/v1")!
        )
        private let bareClient: APIClient
        private let coordinator: TokenRefreshCoordinator
        private let client: APIClient

        init() {
            URLProtocolStub.reset()
            bareClient = APIClient(configuration: configuration, urlSession: URLProtocolStub.makeSession())
            coordinator = TokenRefreshCoordinator(apiClient: bareClient, secureStore: secureStore)
            client = APIClient(
                configuration: configuration,
                urlSession: URLProtocolStub.makeSession(),
                interceptors: [AuthInterceptor(secureStore: secureStore)],
                tokenRefresher: coordinator
            )
        }

        private func seedTokens() throws {
            try secureStore.setString("at_old", forKey: .accessToken)
            try secureStore.setString("rt_old", forKey: .refreshToken)
        }

        private static func requests(toPath path: String) -> [URLRequest] {
            URLProtocolStub.receivedRequests.filter { $0.url?.path() == path }
        }

        @Test func suresiDolmusTokenlaIstekRefreshEdilipTekrarlanirVeBasarir() async throws {
            try seedTokens()
            URLProtocolStub.setHandler { request in
                switch request.url?.path() {
                case "/v1/auth/refresh":
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 200),
                        Data(#"{"accessToken":"at_new","refreshToken":"rt_new"}"#.utf8)
                    )
                case "/v1/feed":
                    if request.value(forHTTPHeaderField: "Authorization") == "Bearer at_new" {
                        return (
                            URLProtocolStub.httpResponse(for: request, status: 200),
                            Data(#"{"value":"ok"}"#.utf8)
                        )
                    }
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                default:
                    return (URLProtocolStub.httpResponse(for: request, status: 404), Data())
                }
            }

            let response = try await client.send(FeedEndpoint())

            #expect(response == FeedPayload(value: "ok"))

            let feedRequests = Self.requests(toPath: "/v1/feed")
            #expect(feedRequests.count == 2)
            #expect(feedRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer at_old")
            #expect(feedRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer at_new")

            // Refresh ucu requiresAuth=false: Bearer TAŞIMAZ (03 §8.2).
            let refreshRequests = Self.requests(toPath: "/v1/auth/refresh")
            #expect(refreshRequests.count == 1)
            #expect(refreshRequests.first?.value(forHTTPHeaderField: "Authorization") == nil)

            // Rotasyon Keychain'e yazıldı.
            #expect(try secureStore.string(forKey: .accessToken) == "at_new")
            #expect(try secureStore.string(forKey: .refreshToken) == "rt_new")
        }

        @Test func esZamanli401lerTekRefreshCagrisiylaKurtarilir() async throws {
            try seedTokens()
            URLProtocolStub.setHandler { request in
                switch request.url?.path() {
                case "/v1/auth/refresh":
                    // Eşzamanlı 401'lerin ilk refresh uçuştayken kuyruklanmasını garanti eder.
                    Thread.sleep(forTimeInterval: 0.2)
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 200),
                        Data(#"{"accessToken":"at_new","refreshToken":"rt_new"}"#.utf8)
                    )
                case "/v1/feed":
                    if request.value(forHTTPHeaderField: "Authorization") == "Bearer at_new" {
                        return (
                            URLProtocolStub.httpResponse(for: request, status: 200),
                            Data(#"{"value":"ok"}"#.utf8)
                        )
                    }
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                default:
                    return (URLProtocolStub.httpResponse(for: request, status: 404), Data())
                }
            }

            let responses = try await withThrowingTaskGroup(of: FeedPayload.self) { [client] group in
                for _ in 0 ..< 5 {
                    group.addTask { try await client.send(FeedEndpoint()) }
                }
                var collected: [FeedPayload] = []
                for try await response in group {
                    collected.append(response)
                }
                return collected
            }

            #expect(responses == Array(repeating: FeedPayload(value: "ok"), count: 5))
            #expect(Self.requests(toPath: "/v1/auth/refresh").count == 1)
        }

        @Test func refreshDeDuserseMisafirYenidenKurulurVeIstekBasarir() async throws {
            // Misafir oturum: refresh zinciri kopunca sessizce POST /auth/guest (05 §4.2).
            try seedTokens()
            let snapshot = StoredSessionSnapshot(userID: "usr_eski", provider: nil)
            try secureStore.setData(JSONEncoder().encode(snapshot), forKey: .sessionSnapshot)

            let session = SessionManager(
                apiClient: bareClient,
                secureStore: secureStore,
                clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
            )
            try await session.bootstrapGuestSessionIfNeeded()
            let recoveringCoordinator = TokenRefreshCoordinator(
                apiClient: bareClient,
                secureStore: secureStore,
                failureHandler: session
            )
            let recoveringClient = APIClient(
                configuration: configuration,
                urlSession: URLProtocolStub.makeSession(),
                interceptors: [AuthInterceptor(secureStore: secureStore)],
                tokenRefresher: recoveringCoordinator
            )

            URLProtocolStub.setHandler { request in
                switch request.url?.path() {
                case "/v1/auth/refresh":
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                case "/v1/auth/guest":
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 200),
                        Data(#"{"userId":"usr_yeni","accessToken":"at_guest","refreshToken":"rt_guest"}"#.utf8)
                    )
                case "/v1/feed":
                    if request.value(forHTTPHeaderField: "Authorization") == "Bearer at_guest" {
                        return (
                            URLProtocolStub.httpResponse(for: request, status: 200),
                            Data(#"{"value":"ok"}"#.utf8)
                        )
                    }
                    return (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                default:
                    return (URLProtocolStub.httpResponse(for: request, status: 404), Data())
                }
            }

            let response = try await recoveringClient.send(FeedEndpoint())

            #expect(response == FeedPayload(value: "ok"))
            #expect(Self.requests(toPath: "/v1/auth/refresh").count == 1)
            #expect(Self.requests(toPath: "/v1/auth/guest").count == 1)
            #expect(session.state == .guest(userID: "usr_yeni"))
            #expect(try secureStore.string(forKey: .accessToken) == "at_guest")
        }

        @Test func bagliHesaptaRefreshDeDuserseOturumDuserVeIstekSessionExpiredIleBiter() async throws {
            try seedTokens()
            let snapshot = StoredSessionSnapshot(userID: "usr_linked", provider: .apple)
            try secureStore.setData(JSONEncoder().encode(snapshot), forKey: .sessionSnapshot)

            let session = SessionManager(
                apiClient: bareClient,
                secureStore: secureStore,
                clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
            )
            try await session.bootstrapGuestSessionIfNeeded()
            let recoveringCoordinator = TokenRefreshCoordinator(
                apiClient: bareClient,
                secureStore: secureStore,
                failureHandler: session
            )
            let recoveringClient = APIClient(
                configuration: configuration,
                urlSession: URLProtocolStub.makeSession(),
                interceptors: [AuthInterceptor(secureStore: secureStore)],
                tokenRefresher: recoveringCoordinator
            )

            URLProtocolStub.setHandler { request in
                switch request.url?.path() {
                case "/v1/auth/refresh":
                    (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                default:
                    (URLProtocolStub.httpResponse(for: request, status: 401), Data())
                }
            }

            await #expect(throws: AppError.auth(.sessionExpired)) {
                _ = try await recoveringClient.send(FeedEndpoint())
            }
            #expect(session.state == .loggedOut(previousUserID: "usr_linked", provider: .apple))
            #expect(Self.requests(toPath: "/v1/auth/guest").isEmpty)
            #expect(try secureStore.string(forKey: .accessToken) == nil)
        }
    }
}
