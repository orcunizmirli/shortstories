import Foundation

/// `GET /config` fetch + UserDefaults cache + flag snapshot köprüsünün canlı
/// uygulaması (SS-024, 05 §4.10). `APIClient` ile çeker, `RemoteConfig`'e decode eder,
/// yükü + zaman damgasını UserDefaults'a cache'ler (24h TTL) ve flag'leri
/// `FeatureFlagStore.persistSnapshot` ile bir SONRAKİ launch için yazar (freeze-per-launch,
/// 03 §11). Ağ yoksa / bozuk yük → GRACEFUL (son cache / kod içi varsayılan; throw yok).
///
/// UserDefaults thread-safe'tir (Apple dokümantasyonu) — `@unchecked Sendable` bu
/// gerekçeyle güvenlidir (`UserDefaultsPreferences` ile aynı kalıp). Durum UserDefaults'ta
/// yaşar; tip değersizdir → eşzamanlı `refresh()` için ayrı serileştirme gerekmez.
public struct RemoteConfigClient: RemoteConfigProviding, @unchecked Sendable {
    /// Cache yükü + zaman damgasının UserDefaults anahtarı (03 §9 UserDefaults satırı).
    public static let cacheDefaultsKey = "remoteConfig.cache"

    /// Cache tazelik penceresi (05 §4.10: "24 saat TTL + arka plan tazeleme").
    public static let cacheTTL: TimeInterval = 24 * 60 * 60

    private let apiClient: any APIClientProtocol
    private let userDefaults: UserDefaults
    private let logger: any Logging
    private let now: @Sendable () -> Date

    public init(
        apiClient: any APIClientProtocol,
        userDefaults: UserDefaults = .standard,
        logger: any Logging,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.logger = logger
        self.now = now
    }

    // MARK: - RemoteConfigProviding

    public func cachedConfig() -> RemoteConfig? {
        loadCache()?.config
    }

    public func isCacheFresh() -> Bool {
        guard let cached = loadCache() else { return false }
        let elapsed = now().timeIntervalSince1970 - cached.fetchedAtEpoch
        // GELECEK-damga (elapsed < 0: cihaz saati ileri→geri alındı, ölü-RTC + NTP düzeltmesi) BAYAT
        // sayılır → yeniden fetch. Aksi halde negatif geçen süre daima < TTL olup cache'i sonsuza
        // "taze" gösterir ve config (flag/experiment/minSupportedVersion) hiç tazelenmezdi.
        return elapsed >= 0 && elapsed < Self.cacheTTL
    }

    @discardableResult
    public func refresh() async -> RemoteConfig? {
        do {
            let config = try await apiClient.send(ConfigEndpoint())
            persist(config)
            // Flag snapshot'ı bir sonraki launch'ta okunur (03 §11 freeze-per-launch);
            // acil kill-switch yeniden-okuma istisnası çağıranın sorumluluğundadır.
            FeatureFlagStore.persistSnapshot(config.flags, to: userDefaults)
            logger.info("config: remote config tazelendi")
            return config
        } catch {
            // GRACEFUL (05 §4.10 / 03 §11 offline): ağ hatası ya da bozuk yük uygulamayı
            // DURDURMAZ. Cache bozuk fetch'te ÜZERİNE YAZILMAZ → son iyi cache korunur.
            // PII kuralı (03 §10.3): hata gövdesi loglanmaz.
            logger.error("config: tazeleme başarısız — cache/varsayılan ile devam")
            return cachedConfig()
        }
    }

    // MARK: - Cache I/O

    private func persist(_ config: RemoteConfig) {
        let envelope = CachedRemoteConfig(config: config, fetchedAtEpoch: now().timeIntervalSince1970)
        // Cache round-trip'i wire tarih stratejisinden bağımsızdır (zaman damgası epoch
        // Double'dır) — sade encoder yeterli; nadir çağrıda taze instance thread-güvenli.
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        userDefaults.set(data, forKey: Self.cacheDefaultsKey)
    }

    /// Cache okur; anahtar yoksa ya da yük bozuksa (şema kayması / kısmi yazma) sessizce
    /// `nil` — çağıran fetch/varsayılan yoluna düşer (asla crash).
    private func loadCache() -> CachedRemoteConfig? {
        guard let data = userDefaults.data(forKey: Self.cacheDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CachedRemoteConfig.self, from: data)
    }
}

/// UserDefaults cache zarfı: config yükü + fetch zaman damgası (epoch saniye). Zaman
/// damgası TTL tazelik kararını (`isCacheFresh`) besler.
struct CachedRemoteConfig: Codable, Sendable, Equatable {
    let config: RemoteConfig
    let fetchedAtEpoch: Double
}
