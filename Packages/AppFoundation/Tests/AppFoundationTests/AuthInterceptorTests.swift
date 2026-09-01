import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

struct AuthInterceptorTests {
    private let secureStore = MockSecureStore()
    private let interceptor: AuthInterceptor
    private let request = URLRequest(url: URL(string: "https://api.test.local/v1/feed")!)
    private let foreignRequest = URLRequest(url: URL(string: "https://evil.cdn.example/asset.m3u8")!)

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

    @Test func apiHostSetliyseYabanciHostaBearerEklemez() async throws {
        // Defense-in-depth (auth hunt LOW): host-scope'lu interceptor Bearer'ı YALNIZ API host'una ekler →
        // yabancı-host (CDN/analytics/3P) isteği zincirden geçse bile kullanıcı token'ı SIZMAZ.
        try secureStore.setString("at_123", forKey: .accessToken)
        let scoped = AuthInterceptor(secureStore: secureStore, apiHost: "api.test.local")

        let adapted = try await scoped.adapt(foreignRequest, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func apiHostSetliyseEslesenHostaBearerEkler() async throws {
        try secureStore.setString("at_123", forKey: .accessToken)
        let scoped = AuthInterceptor(secureStore: secureStore, apiHost: "api.test.local")

        let adapted = try await scoped.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: "Authorization") == "Bearer at_123")
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
