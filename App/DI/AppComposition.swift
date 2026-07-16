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

    init(dependencies: any Dependencies) throws {
        self.dependencies = dependencies
        let apiClient = dependencies.apiClient

        persistence = try PersistenceStore()

        catalog = CatalogAPI(client: apiClient)
        search = SearchAPI(client: apiClient)
        playback = PlaybackAPI(client: apiClient)

        walletStore = WalletStore(
            remote: WalletRemoteClient(client: apiClient),
            analytics: dependencies.analytics,
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

        // Cüzdan satın-alma grafiği: tek StoreKit ürün servisi StorefrontLoader ve satın alma
        // servisi arasında paylaşılır (ürün cache'i tekilleşir).
        let walletRemote = WalletRemoteClient(client: apiClient)
        let products = StoreKitProductService(analytics: dependencies.analytics)
        storeProducts = products
        coinStorefront = StorefrontLoader(remote: walletRemote, products: products)
        let token = UUID()
        appAccountToken = token
        walletPurchasing = PurchaseCoordinator(
            purchases: StoreKitPurchaseService(products: products),
            remote: walletRemote,
            wallet: walletStore,
            analytics: dependencies.analytics,
            log: dependencies.logger,
            appAccountToken: { token }
        )
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
            analytics: dependencies.analytics,
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
            analytics: dependencies.analytics,
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
            analytics: dependencies.analytics,
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
            analytics: dependencies.analytics,
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
            analytics: dependencies.analytics,
            delegate: delegate
        )
    }

    /// Hesap silme modeli — silme/veri-indirme servisi.
    func makeHesapSilmeModel(delegate: (any HesapSilmeDelegate)?) -> HesapSilmeModel {
        HesapSilmeModel(
            deletion: accountDeletionService,
            analytics: dependencies.analytics,
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
            analytics: dependencies.analytics,
            attEnabled: dependencies.featureFlags.value(for: OnboardingFlags.attPromptEnabled),
            onFinish: onFinish
        )
    }

    /// Uygulama sürümü (Profil alt bölgesi) — Info.plist'ten.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
