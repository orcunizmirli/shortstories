import AnalyticsKit
import AppFoundation
import AuthenticationServices
import ContentKit
import DiscoverKit
import Foundation
import LibraryKit
import PlayerKit
import ProfileKit
import RewardsKit
import WalletKit

/// Feature-özel canlı servis + port kompozisyonunun kökü (03 §5 §5.1). `Dependencies` (cross-cutting)
/// üstüne kurulur; disk `PersistenceStore` ve feature-sahipli servisler (`WalletStore`,
/// `LanguagePreferenceService`, `FavoritesService`, `ContinueWatchingService`, katalog/oynatma
/// istemcileri, görev-ilerleme üreticisi, ağ monitörü) BİR KEZ burada kurulur. Feature model'leri
/// `Dependencies` konteynerini DEĞİL yalnız ihtiyaç duydukları DAR portları alır (interface
/// segregation) — seçim aşağıdaki fabrikalarda yapılır.
///
/// R1 istisnası (03 §5): App kompozisyon köküdür ve TÜM feature modüllerini import edebilir; feature↔
/// feature import yasağı (R2) yalnız paketler arası doğrudan bağımlılığı kapsar. Port adaptörleri
/// (`App/DI/Adapters`) tüketici portunu üretici canlı kaynağa köprüler.
///
/// `@MainActor`: kompozisyon ana aktörde kurulur (UI kaynaklı `AppleSignInService`/model fabrikaları
/// main-actor ister). Actor tabanlı servisler (`WalletStore`, `FavoritesService`, ...) cross-actor
/// güvenle kullanılır.
@MainActor
final class AppComposition {
    // MARK: - Cross-cutting (Dependencies)

    let dependencies: any Dependencies

    // MARK: - Kalıcılık (03 §9) — tek disk store; repository'ler buradan

    let persistence: PersistenceStore

    // MARK: - Feature-sahipli canlı servisler (composition-root singletons)

    /// Cüzdan/entitlement otoritatif istemci sahibi (SS-092). `WalletGateway`/`EntitlementChecking`.
    let walletStore: WalletStore
    /// Uygulama + altyazı dili tek kaynağı (SS-161); `SubtitleLanguageProviding`/`AppLanguageProviding`.
    let languagePreferences: LanguagePreferenceService
    /// Favoriler tek kaynak servisi (SS-121).
    let favoritesService: FavoritesService
    /// İzleme geçmişi + "Devam Et" tek kaynak servisi (SS-122).
    let continueWatchingService: ContinueWatchingService
    /// Katalog istemcisi (SS-031) — DiziDetay/Kesfet/Listem JOIN.
    let catalog: any CatalogServicing
    /// Arama servisi (05 §4.8).
    let search: any SearchServicing
    /// Oynatma yetkilendirme servisi (05 §4.4) — PlayerKit havuzu buradan imzalı URL alır.
    let playback: any PlaybackServicing
    /// Görev ilerleme ÜRETİCİSİ (SS-112) — App gerçek olay kaynaklarını buraya besler.
    let taskProgress: LiveTaskProgressStore
    /// Ağ koşulu monitörü (SS-026) — player veri-tasarrufu/bitrate kararları.
    let networkCondition: NWNetworkConditionProvider

    /// APNs cihaz token'ı kayıt servisi (SS-140) — `POST /devices` (idempotent). Onboarding izni +
    /// her açılış (izin varsa) token'ı buraya akıtır; `PushService` sarar.
    let deviceTokenRegistrar: any DeviceTokenRegistering

    // MARK: - Cüzdan satın-alma grafiği (SS-090/091) — WalletKit sheet'leri buradan beslenir

    /// Coin paket kataloğu + StoreKit ürün yükleme portu (CoinMagazasi/VIPAbonelik `StorefrontLoading`).
    let coinStorefront: StorefrontLoader
    /// StoreKit 2 satın alma + backend doğrulama orkestratörü (UnlockSheet dışı satın almalar için
    /// `WalletPurchasing`). Faz 2 sheet'leri (CoinMagazasi/VIPAbonelik) bunu tüketir; App açılışta
    /// `startObservingTransactions()` çağırır (06 §4.4).
    let walletPurchasing: PurchaseCoordinator
    /// StoreKit ürün servisi — hem `StorefrontLoader` hem satın alma servisi tek instance paylaşır.
    private let storeProducts: StoreKitProductService
    /// StoreKit `appAccountToken` — işlemi hesaba bağlar. F1: kurulum-kararlı UUID; SS-021 backend
    /// userId türetimi Faz 2'de bağlanır (TODO).
    private let appAccountToken: UUID

    // MARK: - A/B deney istemcisi (SS-154) — deney boyutu tüm analitik event'lerine düşer

    /// Canlı A/B deney istemcisi (08 §7.1). F1: boş katalog → atama pasif/kontrol (exposure yok).
    let experimentClient: ExperimentClient

    /// `ab_variants` boyutunu HER feature event'ine ekleyen dekoratör; servisler/fabrikalar bunu
    /// `dependencies.analytics` YERİNE alır. İstisna: `ExperimentClient.analytics` BASE kalır (§7.3).
    let decoratedAnalytics: any AnalyticsTracking

    /// Feature'ların deney varyantını okuduğu port (08 §7.3) → canlı `ExperimentClient`.
    var experimentReading: any ExperimentReading {
        experimentClient
    }

    init(dependencies: any Dependencies) throws {
        self.dependencies = dependencies
        let apiClient = dependencies.apiClient

        persistence = try PersistenceStore()

        // SS-154: A/B deney grafiği — persistence SONRASI, analitik-kullanan servislerden ÖNCE kurulur
        // (`decoratedAnalytics` hazır olsun). Kurulum + F1 sınırı TODO'ları `makeExperimentGraph`'ta.
        let experiments = Self.makeExperimentGraph(analytics: dependencies.analytics, secureStore: dependencies.secureStore)
        experimentClient = experiments.client
        decoratedAnalytics = experiments.decorated

        catalog = CatalogAPI(client: apiClient)
        search = SearchAPI(client: apiClient)
        playback = PlaybackAPI(client: apiClient)

        walletStore = WalletStore(
            remote: WalletRemoteClient(client: apiClient),
            analytics: decoratedAnalytics,
            log: dependencies.logger
        )
        languagePreferences = LanguagePreferenceService(preferences: dependencies.preferences)
        favoritesService = FavoritesService(
            repository: persistence.makeFavoritesRepository(),
            remoting: APIFavoritesRemoting(client: apiClient),
            logger: dependencies.logger
        )
        continueWatchingService = ContinueWatchingService(
            repository: persistence.makeWatchHistoryRepository(),
            remoting: APIWatchProgressRemoting(client: apiClient)
        )
        taskProgress = LiveTaskProgressStore()
        networkCondition = NWNetworkConditionProvider()

        // SS-140: cihaz kimliği + kayıt snapshot'ı `SessionManager` ile AYNI Keychain'de (`.deviceID`);
        // token PII değeri UserDefaults'a yazılmaz. Ortam DEBUG/TestFlight'ta sandbox, App Store'da production.
        deviceTokenRegistrar = LiveDeviceTokenRegistrar(
            apiClient: apiClient,
            secureStore: dependencies.secureStore,
            environment: Self.apnsEnvironment,
            logger: dependencies.logger
        )

        // Cüzdan satın-alma grafiği: tek StoreKit ürün servisi StorefrontLoader ve satın alma
        // servisi arasında paylaşılır (ürün cache'i tekilleşir).
        let walletRemote = WalletRemoteClient(client: apiClient)
        let products = StoreKitProductService(analytics: decoratedAnalytics)
        storeProducts = products
        coinStorefront = StorefrontLoader(remote: walletRemote, products: products)
        let token = UUID()
        appAccountToken = token
        walletPurchasing = PurchaseCoordinator(
            purchases: StoreKitPurchaseService(products: products),
            remote: walletRemote,
            wallet: walletStore,
            analytics: decoratedAnalytics,
            log: dependencies.logger,
            appAccountToken: { token }
        )
    }

    /// SS-154 deney grafiği: userID = deviceID (Keychain kalıcı → sticky atama). F1: boş katalog + boş
    /// `previouslyExposed` (default) → atama pasif, exposure yok. `ab_variants` dekoratörü BASE'i sarar
    /// (§7.3 exposure BASE'e gider). TODO(F1): previouslyExposed persist (scenePhase bg) + katalog (SS-024).
    private static func makeExperimentGraph(
        analytics: any AnalyticsTracking,
        secureStore: any SecureStoring
    ) -> (client: ExperimentClient, decorated: ExperimentDimensionTracker) {
        let deviceID = (try? secureStore.string(forKey: .deviceID)) ?? ""
        let client = ExperimentClient(
            catalog: ExperimentCatalog(experiments: []),
            analytics: analytics,
            userID: deviceID
        )
        // `abVariants` closure `@Sendable` (`ExperimentClient` `@unchecked Sendable`, kilitli okuma).
        return (client, ExperimentDimensionTracker(base: analytics, abVariants: { client.abVariantsParameter() }))
    }

    // MARK: - Port adaptörleri (canlı — Faz 2 sekme view'ları bu fabrikaları kullanır)

    /// RewardsKit coin-bakiyesi okuma portu → WalletKit `WalletGateway`.
    var rewardsWalletReading: any RewardsWalletReading {
        WalletGatewayRewardsReading(gateway: walletStore)
    }

    /// ProfileKit cüzdan-özeti okuma portu → WalletKit `WalletGateway`.
    var walletSummaryReading: any WalletSummaryReading {
        WalletGatewaySummaryReading(gateway: walletStore)
    }

    /// RewardsKit check-in servisi → `APIClient` (/rewards/checkin).
    var checkInService: any CheckInService {
        APICheckInService(client: dependencies.apiClient)
    }

    /// RewardsKit görev-claim servisi → `APIClient` (/missions/{id}/claim).
    var rewardClaiming: any RewardClaiming {
        APIRewardClaiming(client: dependencies.apiClient)
    }

    /// RewardsKit görev kataloğu → `APIClient` (/missions).
    var taskCatalog: any TaskCatalogProviding {
        APITaskCatalogProvider(client: dependencies.apiClient)
    }

    /// RewardsKit son-görülen streak kalıcılığı → UserDefaults.
    let lastSeenStreakStore: any LastSeenStreakStoring = UserDefaultsLastSeenStreakStore()

    /// LibraryKit Listem JOIN portu → ContentKit katalog + AppFoundation katalog cache (offline-önce).
    /// Bölüm-ID → dizi çözümü izleme geçmişi tek kaynağından (`ContinueWatchingService`) gelir.
    var libraryCatalogReading: any LibraryCatalogReading {
        let continueWatching = continueWatchingService
        return CatalogLibraryReading(
            catalog: catalog,
            cache: persistence.makeCatalogCacheStore(),
            resolveSeries: { episodeIDs in
                var map: [EpisodeID: SeriesID] = [:]
                for episodeID in episodeIDs {
                    if let record = try? await continueWatching.progress(forEpisode: episodeID) {
                        map[episodeID] = record.seriesID
                    }
                }
                return map
            }
        )
    }

    /// DiscoverKit DiziDetay izleme-geçmişi portu → LibraryKit `ContinueWatchingService`.
    var discoverWatchHistoryReading: any DiscoverKit.WatchHistoryReading {
        ContinueWatchingHistoryReading(service: continueWatchingService)
    }

    /// DiscoverKit DiziDetay favori köprüsü → LibraryKit `FavoritesService`.
    var discoverFavoritesGateway: any DiscoverKit.FavoritesGateway {
        FavoritesServiceGateway(service: favoritesService)
    }

    /// ProfileKit hesap-bağlama servisi → `APIClient` + canlı `SessionManager` (linkSession hook'u
    /// oturumu `.linked`e yükseltir + Keychain'e yazar).
    var accountLinkingService: any AccountLinkingServicing {
        APIAccountLinkingService(client: dependencies.apiClient, session: dependencies.session)
    }

    /// ProfileKit hesap-silme + veri-indirme servisi → `APIClient`.
    var accountDeletionService: any AccountDeletionServicing {
        APIAccountDeletionService(client: dependencies.apiClient)
    }

    /// PlayerKit oynatma-tercihi portu (veri tasarrufu) → `PreferencesStoring`.
    var playerDataSaverProvider: any PlayerKit.PlaybackPreferencesProviding {
        PreferencesDataSaverProvider(preferences: dependencies.preferences)
    }

    /// PlayerKit video-cache LRU indeksi → tek `PersistenceStore`.
    var assetCacheIndex: any AssetCacheIndexing {
        persistence.makeAssetCacheIndex()
    }

    // MARK: - PlayerKit oynatma grafiği (04 §2.4 — havuz/prefetch kompozisyon kökünde)

    /// Player havuzu (3–5 instance): imzalı URL + entitlement + ağ + veri tasarrufu portlarıyla.
    /// `PlayerFeedView`'a init-injection ile verilir (Dependencies konteynerine KONMAZ).
    func makePlayerPool(size: Int = 3) -> PlayerPool {
        PlayerPool(
            size: size,
            playback: playback,
            entitlements: walletStore,
            network: networkCondition,
            preferences: playerDataSaverProvider,
            logger: dependencies.logger
        )
    }

    /// Sonraki-bölüm ön-yükleme denetleyicisi (havuza bağlı).
    func makePrefetchController(pool: PlayerPool) -> PrefetchController {
        PrefetchController(pool: pool, network: networkCondition, preferences: playerDataSaverProvider)
    }

    // MARK: - Ekran modeli fabrikaları (Faz 2 delegate'i geçirir; portlar burada bağlanır)

    /// OdulMerkezi (Ödüller) modeli — tüm RewardsKit portları canlı bağlı.
    func makeOdulMerkeziModel(delegate: (any RewardsDelegate)?) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: checkInService,
            wallet: rewardsWalletReading,
            taskCatalog: taskCatalog,
            taskProgress: taskProgress,
            rewardClaiming: rewardClaiming,
            analytics: decoratedAnalytics,
            featureFlags: dependencies.featureFlags,
            delegate: delegate,
            lastSeenStreakStore: lastSeenStreakStore
        )
    }

    /// Listem modeli — Favoriler/Devam Et servisleri + katalog JOIN.
    func makeListemModel(delegate: (any ListemDelegate)?) -> ListemModel {
        ListemModel(
            favoritesService: favoritesService,
            continueWatchingService: continueWatchingService,
            catalog: libraryCatalogReading,
            analytics: decoratedAnalytics,
            delegate: delegate
        )
    }

    /// Profil modeli — oturum + cüzdan özeti + uygulama dili.
    func makeProfilModel(
        delegate: (any ProfileDelegate)?,
        appVersion: String = AppComposition.appVersion,
        notificationCenterEnabled: Bool = false
    ) -> ProfilModel {
        ProfilModel(
            session: dependencies.session,
            walletSummary: walletSummaryReading,
            analytics: decoratedAnalytics,
            delegate: delegate,
            appLanguage: languagePreferences,
            appVersion: appVersion,
            notificationCenterEnabled: notificationCenterEnabled
        )
    }

    /// Ayarlar modeli — tercih deposu + dil servisi + (opsiyonel) bildirim izni durumu.
    func makeAyarlarModel(
        delegate: (any SettingsDelegate)?,
        notificationPermission: (any NotificationPermissionStatusProviding)? = nil
    ) -> AyarlarModel {
        AyarlarModel(
            preferences: dependencies.preferences,
            language: languagePreferences,
            analytics: decoratedAnalytics,
            delegate: delegate,
            notificationPermission: notificationPermission
        )
    }

    /// Hesap bağlama modeli — canlı `AppleSignInService` (sunum çıpası App'ten) + backend bağlama.
    func makeHesapBaglamaModel(
        anchor: @escaping @MainActor () -> ASPresentationAnchor,
        delegate: (any HesapBaglamaDelegate)?
    ) -> HesapBaglamaModel {
        HesapBaglamaModel(
            appleSignIn: AppleSignInService(anchor: anchor),
            linking: accountLinkingService,
            analytics: decoratedAnalytics,
            delegate: delegate
        )
    }

    /// Hesap silme modeli — silme/veri-indirme servisi.
    func makeHesapSilmeModel(delegate: (any HesapSilmeDelegate)?) -> HesapSilmeModel {
        HesapSilmeModel(
            deletion: accountDeletionService,
            analytics: decoratedAnalytics,
            delegate: delegate
        )
    }

    /// Onboarding modeli (SS-064) — dil `LanguagePreferenceService`'e yazılır, tür `PreferencesStoring`'e
    /// persist edilir; bildirim izni + ATT canlı sistem sarmalarına (port arkası) bağlanır. ATT bayrağı
    /// remote config'ten okunur (08 §9.1 — Faz 1 kapalı). `onFinish` Faz 2 launch routing'e bağlanır.
    func makeOnboardingModel(
        onFinish: (@MainActor (OnboardingModel.Completion) -> Void)? = nil
    ) -> OnboardingModel {
        OnboardingModel(
            initialLanguage: languagePreferences.appLanguage,
            genreOptions: OnboardingGenreCatalog.embedded,
            language: languagePreferences,
            preferences: dependencies.preferences,
            notifications: LiveNotificationAuthorizationRequester(),
            tracking: LiveAppTrackingRequester(),
            analytics: decoratedAnalytics,
            attEnabled: dependencies.featureFlags.value(for: OnboardingFlags.attPromptEnabled),
            // SS-140: bildirim izni VERİLİNCE APNs kaydını tetikle (canlı UIApplication sarması).
            remoteNotifications: LiveRemoteNotificationRegistering(),
            onFinish: onFinish
        )
    }

    /// SS-140/143 push orkestratörü (`AppDelegate` bunu bağlar). `dispatch` çözülmüş push rotasını
    /// launch katmanına akıtır (soğuk açılış PendingRoute mantığı orada). `optIn` = ProfileKit ana
    /// bildirim anahtarı (`POST /devices notificationOptIn`).
    func makePushService(
        dispatch: @escaping @MainActor (DeepLinkRoute, DeepLinkSource) -> Void
    ) -> PushService {
        let preferences = dependencies.preferences
        return PushService(
            registrar: deviceTokenRegistrar,
            analytics: decoratedAnalytics,
            remoteRegistration: LiveRemoteNotificationRegistering(),
            authorization: LiveNotificationAuthorizationReader(),
            optInProvider: { NotificationPreferences.read(from: preferences).primaryEnabled },
            dispatch: dispatch
        )
    }

    /// APNs teslim ortamı (05 §4.9 `environment`): DEBUG/TestFlight sandbox, App Store production token.
    static var apnsEnvironment: APNsEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }

    /// Uygulama sürümü (Profil alt bölgesi) — Info.plist'ten.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
