import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

struct AuthInterceptorTests {
    private let secureStore = MockSecureStore()
    private let interceptor: AuthInterceptor
    private let request = URLRequest(url: URL(string: "https://api.test.local/v1/feed")!)

    init() {
        interceptor = AuthInterceptor(secureStore: secureStore)
    }

    @Test func authGerektirenIstegeBearerHeaderEkler() async throws {
        try secureStore.setString("at_123", forKey: .accessToken)

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: "Authorization") == "Bearer at_123")
    }

    @Test func authGerektirmeyenIstegeHeaderEklemez() async throws {
        try secureStore.setString("at_123", forKey: .accessToken)

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: false))

        #expect(adapted.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func tokenYoksaHeaderEklemedenGecirir() async throws {
        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func mevcutHeaderVeUrlKorunur() async throws {
        try secureStore.setString("at_123", forKey: .accessToken)
        var original = request
        original.setValue("tr-TR", forHTTPHeaderField: "Accept-Language")

        let adapted = try await interceptor.adapt(original, context: RequestContext(requiresAuth: true))

        #expect(adapted.url == original.url)
        #expect(adapted.value(forHTTPHeaderField: "Accept-Language") == "tr-TR")
    }
}
