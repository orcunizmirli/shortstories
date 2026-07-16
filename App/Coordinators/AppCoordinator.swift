import AppFoundation
import DiscoverKit
import Foundation
import Observation

/// Uygulama yaşam döngüsü + launch routing kompozisyon kökü (03 §3.1). Launch durum makinesi
/// (`Splash → Onboarding | Tabs`) ayrı, kompozisyon-bağımsız `LaunchCoordinator`'da yaşar (birim test
/// edilebilir); bu tip canlı işbirlikçileri (çekirdek ön-yükleme, onboarding modeli fabrikası, Tab
/// delegasyonu) kompozisyon kökünden ona bağlar. Deep link giriş noktası (`open`) burada URL'i çözer,
/// yönlendirmeyi `LaunchCoordinator`'a bırakır (soğuk açılışta `PendingRoute`, 03 §3.2 kural 6).
@Observable
@MainActor
final class AppCoordinator {
    /// Launch routing durum makinesi (Splash/Onboarding/Tabs) — kök görünüm buna göre çizilir.
    let launch: LaunchCoordinator
    let tabCoordinator: TabCoordinator

    /// Feature-özel canlı servis + port kompozisyonu (03 §5): BİR KEZ kompozisyon kökünde kurulur.
    let composition: AppComposition
    private let dependencies: any Dependencies

    init(dependencies: any Dependencies, composition: AppComposition) {
        self.dependencies = dependencies
        self.composition = composition
        let tabCoordinator = TabCoordinator(composition: composition)
        self.tabCoordinator = tabCoordinator

        // Canlı işbirlikçileri closure ile bağla (LaunchCoordinator kompozisyona bağımlı DEĞİL; test
        // edilebilirlik için). Closure'lar `self`'i DEĞİL yalnız gereken servisleri yakalar → döngü yok.
        launch = LaunchCoordinator(
            preferences: dependencies.preferences,
            preload: { await Self.coldStartPreload(dependencies: dependencies, composition: composition) },
            makeOnboarding: { onFinish in composition.makeOnboardingModel(onFinish: onFinish) },
            dispatchToTabs: { route, source in tabCoordinator.handle(route, source: source) }
        )
    }

    // MARK: - SS-060 çekirdek ön-yükleme (Splash arka planı)

    /// Splash sırasında çalışan cold-start ön-yükleme (SS-060). Kritik yol (feed'in imzalı URL için
    /// ihtiyaç duyduğu misafir oturumu) beklenir; kritik-olmayan/yavaş işler (cüzdan gözlem + tazeleme)
    /// arka plana atılır → splash asılı kalmaz. `static`: `self` yakalamadan çağrılır (döngü yok).
    private static func coldStartPreload(
        dependencies: any Dependencies,
        composition: AppComposition
    ) async {
        // SS-021: anonim misafir oturumu (zaten varsa no-op). API client timeout'lu → asılı kalmaz;
        // hata sessiz (feed kendi durumunu gösterir).
        _ = try? await dependencies.session.bootstrapGuestSessionIfNeeded()

        // TODO(SS-060/SS-062/SS-042): ilk feed sayfası + ilk video prefetch tetiği. App feed yükleme
        //   dilimi (SS-062) `PlayerFeedViewModel.feedState`e ilk sayfayı seed edip PrefetchController'ı
        //   (SS-042) ilk videonun ~500 KB / ilk 2 sn'si için tetikleyecek; böylece Splash → ilk kare
        //   cold-start bütçesi içinde kalır. Feed yükleme yüzeyi henüz bağlı olmadığından (F1 iskelet)
        //   şimdilik feed kendi yükleme durumunu gösterir; hazır olunca await buraya taşınır.

        // Kritik-olmayan/yavaş işler arka planda — splash geçişini bloke etmez:
        Task {
            // SS-090/091: önceki oturumdan kalan unfinished transaction'ları drenajla + canlı updates.
            await composition.walletPurchasing.startObservingTransactions()
            // SS-092: cüzdan/entitlement otoritatif tazeleme.
            await composition.walletStore.refresh()
        }
    }

    // MARK: - Deep link (SS-142)

    /// Universal link / custom scheme / push URL'ini çözer ve `LaunchCoordinator`'a yönlendirir.
    /// Çözülemeyen URL yutulur. Soğuk açılışta (Splash/Onboarding) rota bekletilir; Tab'lara geçince işlenir.
    func open(_ url: URL) {
        guard let route = DeepLinkRoute(url: url) else { return }
        launch.dispatch(route, source: Self.source(for: url))
    }

    /// Deep link menşeini scheme'den türetir (02 §8.4 kural 5): `https/http` → universal link;
    /// custom scheme → uygulama içi/push (push ayrımı APNs kancası SS-140'ta netleşir, F1'de internal).
    private static func source(for url: URL) -> DeepLinkSource {
        switch url.scheme?.lowercased() {
        case "https", "http": .universal
        default: .appInternal
        }
    }
}
