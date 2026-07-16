import AppFoundation
import DiscoverKit
import Foundation
import Observation

/// SS-060 / SS-064 — Launch routing DURUM MAKİNESİ (03 §3.1): `Splash → Onboarding | Tabs`. Soğuk
/// açılışta önce Splash gösterilir; arka planda çekirdek ön-yükleme (misafir oturumu + ilk feed/video
/// prefetch tetiği) sürerken minimum splash zemini beklenir (SS-060 cold-start bütçesi). Ön-yükleme
/// hazır olunca `onboardingCompleted` bayrağına göre Onboarding'e ya da doğrudan Tab'lara geçilir;
/// onboarding tamamlanınca (completed/skipped) Tab'lara geçiş yapılır.
///
/// Tasarım: `AppComposition`'a BAĞIMSIZ tutulur (dar port + closure injection) → durum makinesi ağır
/// kompozisyon kökü kurmadan birim test edilir (OnboardingModel kalıbı). Canlı closure'lar App
/// kompozisyon kökünde (`AppCoordinator`) bağlanır. Deep-link soğuk-açılış `PendingRoute` mantığı
/// (03 §3.2 kural 6) burada yaşar: Splash/Onboarding sırasında gelen rota düşürülmez, Tab'lara
/// geçince işlenir.
@Observable
@MainActor
final class LaunchCoordinator {
    /// Uygulama kök görünüm durumu (03 §3.1). Başlangıç `.splash` — soğuk açılış her zaman Splash'tan başlar.
    enum LaunchState: Equatable, Sendable {
        case splash
        case onboarding
        case tabs
    }

    private(set) var launchState: LaunchState = .splash
    /// `.onboarding` durumunda `OnboardingView`'a verilecek model; diğer durumlarda `nil`.
    private(set) var onboardingModel: OnboardingModel?

    /// Soğuk açılışta root (Tab'lar) hazır olmadan gelen deep link burada bekletilir; Splash/Onboarding
    /// rotayı düşürmez (03 §3.2 kural 6). `.tabs`'e geçince işlenir.
    private(set) var pendingRoute: DeepLinkRoute?
    /// Bekleyen rotanın menşei — işlenince `deeplink_opened.source` doğru kalsın diye saklanır.
    private var pendingRouteSource: DeepLinkSource = .appInternal

    // MARK: - Enjekte edilen işbirlikçiler (kompozisyon-bağımsız)

    private let preferences: any PreferencesStoring
    /// Çekirdek ön-yükleme (SS-060): misafir oturumu bootstrap + cüzdan gözlem/tazeleme + ilk feed/video
    /// prefetch tetiği. Splash bunu bekler (bounded: canlı uygulama yavaş işleri arka plana atar).
    private let preload: @MainActor () async -> Void
    /// Onboarding modeli fabrikası — tamamlanınca (completed/skipped) verilen closure çağrılır.
    private let makeOnboarding: @MainActor (@escaping @MainActor (OnboardingModel.Completion) -> Void) -> OnboardingModel
    /// Çözülmüş rotayı Tab katmanına (TabCoordinator) delege eder.
    private let dispatchToTabs: @MainActor (DeepLinkRoute, DeepLinkSource) -> Void
    /// Minimum splash görünme süresi (cold-start bütçesi): ön-yükleme daha hızlı bitse bile logo bu
    /// süre boyunca görünür (ani sıçrama önlenir); daha yavaşsa ön-yükleme süresi belirler (max'i alınır).
    private let minimumSplashDuration: Duration
    /// Uyku enjeksiyonu — testler no-op geçerek splash zeminini anında geçer (deterministik).
    private let sleep: (Duration) async -> Void

    private var didBeginLaunch = false

    init(
        preferences: any PreferencesStoring,
        preload: @escaping @MainActor () async -> Void,
        makeOnboarding: @escaping @MainActor (@escaping @MainActor (OnboardingModel.Completion) -> Void) -> OnboardingModel,
        dispatchToTabs: @escaping @MainActor (DeepLinkRoute, DeepLinkSource) -> Void,
        minimumSplashDuration: Duration = .milliseconds(600),
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.preferences = preferences
        self.preload = preload
        self.makeOnboarding = makeOnboarding
        self.dispatchToTabs = dispatchToTabs
        self.minimumSplashDuration = minimumSplashDuration
        self.sleep = sleep
    }

    // MARK: - Launch dizisi (Splash → …)

    /// Splash göründüğünde çağrılır (`SplashView` `.task`). Idempotent: launch dizisi yalnız bir kez sürer.
    func beginLaunch() {
        guard !didBeginLaunch else { return }
        didBeginLaunch = true
        Task { await runLaunchSequence() }
    }

    /// Launch dizisini yürütür. `beginLaunch()` bunu fire-and-forget çağırır; testler doğrudan `await` eder
    /// (deterministik). Toplam splash süresi = max(ön-yükleme, minimum zemin) — SS-060 cold-start bütçesi.
    func runLaunchSequence() async {
        let clock = ContinuousClock()
        let started = clock.now
        // "Hazır olunca geçiş": çekirdek ön-yükleme (oturum + ilk feed prefetch tetiği) beklenir.
        await preload()
        // Minimum splash zemini: ön-yükleme çok hızlıysa kalan süre kadar logo görünür kalır.
        let remaining = minimumSplashDuration - started.duration(to: clock.now)
        if remaining > .zero {
            await sleep(remaining)
        }
        advanceFromSplash()
    }

    /// Splash'tan sonraki hedefi seçer: onboarding gerekiyorsa Onboarding, değilse doğrudan Tab'lar.
    private func advanceFromSplash() {
        guard launchState == .splash else { return }
        if needsOnboarding {
            presentOnboarding()
        } else {
            enterTabs()
        }
    }

    /// Onboarding gerekli mi (03 §3.1 / KEYS: `onboardingCompleted` tek kaynak). İlk açılışta `false` →
    /// onboarding gösterilir; tamamlanınca model bayrağı `true` yazar → tekrar açılışta atlanır.
    var needsOnboarding: Bool {
        !preferences.value(for: PreferenceKeys.onboardingCompleted)
    }

    private func presentOnboarding() {
        onboardingModel = makeOnboarding { [weak self] _ in
            self?.completeOnboarding()
        }
        launchState = .onboarding
    }

    /// Onboarding tamamlandığında (completed/skipped) çağrılır — her iki sonuçta da Tab'lara geçilir
    /// (bayrağı `OnboardingModel` zaten yazdı; bir daha gösterilmez).
    private func completeOnboarding() {
        guard launchState == .onboarding else { return }
        enterTabs()
    }

    private func enterTabs() {
        launchState = .tabs
        onboardingModel = nil
        flushPendingRouteIfNeeded()
    }

    // MARK: - Deep link (SS-142, 03 §3.2 kural 6)

    /// Çözülmüş rotayı yönlendirir: Tab'lar hazırsa hemen delege eder, değilse `PendingRoute` olarak saklar.
    func dispatch(_ route: DeepLinkRoute, source: DeepLinkSource = .appInternal) {
        switch launchState {
        case .tabs:
            dispatchToTabs(route, source)
        case .splash, .onboarding:
            pendingRoute = route
            pendingRouteSource = source
        }
    }

    private func flushPendingRouteIfNeeded() {
        guard launchState == .tabs, let route = pendingRoute else { return }
        let source = pendingRouteSource
        pendingRoute = nil
        dispatchToTabs(route, source)
    }
}
