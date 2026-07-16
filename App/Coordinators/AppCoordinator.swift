import AppFoundation
import DiscoverKit
import Foundation
import Observation

/// Uygulama yaşam döngüsü + launch routing koordinatörü (03 §3.1). F1 iskeleti: doğrudan
/// `TabCoordinator`'a geçer (Splash/Onboarding SS-064 ayrı bir dilim). Deep link çözümü
/// (`PendingRoute`) temel iskeleti burada: soğuk açılışta rota saklanır, kök hazır olunca işlenir
/// (03 §3.2 kural 6). Zorunlu güncelleme/bakım overlay'leri Faz 2.
@Observable
@MainActor
final class AppCoordinator {
    enum LaunchState {
        case splash
        case onboarding
        case tabs
    }

    /// F1: Splash/Onboarding akışı henüz yok — sabit `.tabs` (uygulama doğrudan video ile açılır).
    private(set) var launchState: LaunchState = .tabs

    let tabCoordinator: TabCoordinator

    /// Soğuk açılışta root hazır olmadan gelen deep link burada bekletilir (Splash/Onboarding rotayı
    /// düşürmez, 03 §3.2 kural 6). Root `.tabs`'e geçince işlenir.
    private(set) var pendingRoute: DeepLinkRoute?
    /// Bekleyen rotanın menşei — soğuk açılış işlenince `deeplink_opened.source` doğru kalsın diye
    /// rota ile birlikte saklanır.
    private var pendingRouteSource: DeepLinkSource = .appInternal

    private let dependencies: any Dependencies
    /// Feature-özel canlı servis + port kompozisyonu (03 §5): BİR KEZ kompozisyon kökünde kurulur.
    let composition: AppComposition

    init(dependencies: any Dependencies, composition: AppComposition) {
        self.dependencies = dependencies
        self.composition = composition
        tabCoordinator = TabCoordinator(composition: composition)
    }

    // MARK: - Başlatma

    /// Kök görünüm belirdiğinde çağrılır (`ShortSeriesApp` `.task`). Misafir oturumu bootstrap eder,
    /// cüzdan transaction gözlemcisini başlatır (06 §4.4) ve bekleyen deep link'i işler.
    func start() {
        let session = dependencies.session
        let composition = composition
        Task {
            // SS-021: anonim misafir oturumu (zaten varsa no-op). Hata sessiz — feed kendi durumunu gösterir.
            _ = try? await session.bootstrapGuestSessionIfNeeded()
            // SS-090/091: önceki oturumdan kalan unfinished transaction'ları drenajla + canlı updates.
            await composition.walletPurchasing.startObservingTransactions()
            // SS-092: cüzdan/entitlement otoritatif tazeleme.
            await composition.walletStore.refresh()
        }
        processPendingRouteIfReady()
    }

    // MARK: - Deep link (SS-142)

    /// Universal link / custom scheme / push URL'ini çözer ve yönlendirir. Çözülemeyen URL yutulur.
    func open(_ url: URL) {
        guard let route = DeepLinkRoute(url: url) else { return }
        dispatch(route, source: Self.source(for: url))
    }

    /// Deep link menşeini scheme'den türetir (02 §8.4 kural 5): `https/http` → universal link;
    /// custom scheme → uygulama içi/push (push ayrımı APNs kancası SS-140'ta netleşir, F1'de internal).
    private static func source(for url: URL) -> DeepLinkSource {
        switch url.scheme?.lowercased() {
        case "https", "http": .universal
        default: .appInternal
        }
    }

    /// Çözülmüş rotayı yönlendirir; root hazır değilse `PendingRoute` olarak (menşei ile) saklar.
    func dispatch(_ route: DeepLinkRoute, source: DeepLinkSource = .appInternal) {
        switch launchState {
        case .tabs:
            tabCoordinator.handle(route, source: source)
        case .splash, .onboarding:
            pendingRoute = route
            pendingRouteSource = source
        }
    }

    private func processPendingRouteIfReady() {
        guard launchState == .tabs, let route = pendingRoute else { return }
        let source = pendingRouteSource
        pendingRoute = nil
        tabCoordinator.handle(route, source: source)
    }

    // TODO(SS-064): SessionState'e göre launch routing — Splash → Onboarding | Tabs (03 §3.1).
    //               launchState .tabs sabitten çıkınca `processPendingRouteIfReady()` geçiş sonrası çağrılır.
}
