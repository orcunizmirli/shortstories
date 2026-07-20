import Foundation
import Testing
@testable import AppFoundation
@testable import AppFoundationTestSupport

/// Testte kontrol edilebilir saat — `now` closure'ı bunu okur (TTL sınırı için).
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) {
        current = start
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

struct RemoteConfigClientTests {
    private let fullConfigJSON = """
    {
      "minSupportedVersion": "1.2.0",
      "coinProducts": ["c.tier1", "c.tier2"],
      "vipProducts": ["v.weekly"],
      "adUnlockDailyCap": 7,
      "flags": { "rewardedAdsEnabled": true, "someCap": 8 },
      "experiments": [ { "key": "paywall_layout", "variant": "B" } ]
    }
    """

    // MARK: - Kurulum yardımcıları

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "RemoteConfigClientTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func makeClient(
        api: MockAPIClient,
        defaults: UserDefaults,
        clock: TestClock
    ) -> RemoteConfigClient {
        RemoteConfigClient(
            apiClient: api,
            userDefaults: defaults,
            logger: MockLogger(),
            now: { clock.now }
        )
    }

    // MARK: - Fetch → cache → flag snapshot

    @Test func refreshDekodeEderCacheVeFlagSnapshotYazar() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let client = makeClient(api: api, defaults: defaults, clock: TestClock(Date()))

        let config = try #require(await client.refresh())
        #expect(config.minSupportedVersion == "1.2.0")
        #expect(config.adUnlockDailyCap == 7)
        #expect(config.experiments == [RemoteExperimentAssignment(key: "paywall_layout", variant: "B")])

        // Cache YAZILDI: senkron okuma aynı config'i verir.
        #expect(client.cachedConfig()?.minSupportedVersion == "1.2.0")

        // Flag'ler FeatureFlagStore snapshot'ına köprülendi (bir sonraki launch okuması).
        let flags = FeatureFlagStore(userDefaults: defaults)
        #expect(flags.value(for: FlagKey(name: "rewardedAdsEnabled", default: false)) == true)
        #expect(flags.value(for: FlagKey(name: "someCap", default: 0)) == 8)
    }

    // MARK: - Soğuk açılış / TTL

    @Test func tazeCacheColdStartAgCagrisiYapmaz() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let client = makeClient(api: api, defaults: defaults, clock: clock)

        _ = await client.refresh() // T0'da cache stamp'lenir
        clock.now = Date(timeIntervalSince1970: 1_000_000 + 3600) // +1 saat, TTL içinde

        #expect(client.isCacheFresh())
        let config = await client.loadForColdStart()
        #expect(config?.minSupportedVersion == "1.2.0")
        // Yalnız ilk refresh ağa gitti — taze cache ikinci çağrıyı engelledi.
        #expect(api.receivedPaths == ["/config"])
    }

    @Test func bayatCacheColdStartFetchTetikler() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let client = makeClient(api: api, defaults: defaults, clock: clock)

        _ = await client.refresh() // T0
        clock.now = Date(timeIntervalSince1970: 1_000_000 + 25 * 3600) // +25 saat, TTL AŞILDI

        #expect(!client.isCacheFresh())
        _ = await client.loadForColdStart()
        #expect(api.receivedPaths == ["/config", "/config"]) // bayat → yeniden fetch
    }

    @Test func ttlTazeBayatSiniri() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let clock = TestClock(t0)
        let client = makeClient(api: api, defaults: defaults, clock: clock)

        _ = await client.refresh()

        // TTL'den 1 sn önce: TAZE.
        clock.now = t0.addingTimeInterval(RemoteConfigClient.cacheTTL - 1)
        #expect(client.isCacheFresh())
        // Tam TTL sınırı (>=): BAYAT.
        clock.now = t0.addingTimeInterval(RemoteConfigClient.cacheTTL)
        #expect(!client.isCacheFresh())
    }

    @Test func gelecekDamgaliCacheBayatSayilir() async throws {
        // Saat-kayması savunması (review): fetchedAtEpoch GELECEKte ise (kullanıcı cihaz saatini
        // ileri alıp cache'ler sonra geri döner; ölü-RTC + NTP düzeltmesi), negatif geçen süre < TTL
        // olduğundan cache SONSUZA taze görünür ve config (flag/experiment/minSupportedVersion) hiç
        // tazelenmezdi. Gelecek-damga BAYAT sayılmalı (elapsed < 0 → yeniden fetch).
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let clock = TestClock(t0)
        let client = makeClient(api: api, defaults: defaults, clock: clock)

        _ = await client.refresh() // T0'da damgalanır
        clock.now = t0.addingTimeInterval(-3600) // saat 1 saat GERİYE → damga gelecekte

        #expect(!client.isCacheFresh()) // gelecek-damga bayat
        _ = await client.loadForColdStart()
        #expect(api.receivedPaths == ["/config", "/config"]) // bayat → yeniden fetch
    }

    // MARK: - Graceful offline / hata izolasyonu

    @Test func offlineCacheVarsaOnuDonerFirlatMaz() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let client = makeClient(api: api, defaults: defaults, clock: TestClock(Date()))

        _ = await client.refresh() // cache dolu
        api.stub("/config", throwing: .network(.offline)) // ağ gitti

        // refresh throw ETMEZ; son cache'i döner (uygulama durmaz).
        let config = await client.refresh()
        #expect(config?.minSupportedVersion == "1.2.0")
    }

    @Test func offlineCacheYoksaNilDoner() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", throwing: .network(.offline))
        let client = makeClient(api: api, defaults: defaults, clock: TestClock(Date()))

        let config = await client.refresh()
        #expect(config == nil) // varsayılana düşülür (FeatureFlagStore kod içi default'lar)
        #expect(client.cachedConfig() == nil)
    }

    @Test func bozukYukOncekiCacheyiKorur() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MockAPIClient()
        api.stub("/config", with: .success(Data(fullConfigJSON.utf8)))
        let client = makeClient(api: api, defaults: defaults, clock: TestClock(Date()))

        _ = await client.refresh() // iyi cache
        api.stub("/config", with: .success(Data("<<bozuk json>>".utf8))) // decode edilemez yük

        let config = await client.refresh()
        // Bozuk fetch cache'i EZMEZ; son iyi config döner.
        #expect(config?.minSupportedVersion == "1.2.0")
        #expect(client.cachedConfig()?.minSupportedVersion == "1.2.0")
    }

    @Test func bozukCacheGracefulNil() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // UserDefaults'a çöp yaz (kısmi yazma / şema kayması senaryosu).
        defaults.set(Data("garbage".utf8), forKey: RemoteConfigClient.cacheDefaultsKey)
        let client = makeClient(api: MockAPIClient(), defaults: defaults, clock: TestClock(Date()))

        #expect(client.cachedConfig() == nil) // crash yok
        #expect(!client.isCacheFresh())
    }

    // MARK: - Endpoint sözleşmesi

    @Test func configEndpointGetIdempotentVeAuthsiz() throws {
        let endpoint = ConfigEndpoint()
        #expect(endpoint.path == "/config")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth == false)
        #expect(endpoint.retryPolicy == .default)

        // GET → otomatik retry uygun (03 §8.3 idempotent).
        let apiClient = try APIClient(
            configuration: APIConfiguration(
                environment: .development,
                baseURL: #require(URL(string: "https://api.test.local/v1"))
            )
        )
        #expect(apiClient.isIdempotent(endpoint))
    }
}
