import AppFoundation
import DesignSystem
import SwiftUI
import WalletKit

/// Uygulama giriş noktası ve kompozisyon kökü (03 §5): canlı bağımlılıklar
/// BİR KEZ burada kurulur, `AppCoordinator`/`TabCoordinator` hiyerarşisi buradan sürer.
@main
struct ShortSeriesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Foreground'a dönüş → APNs token/izin senkronu (SS-140 token rotasyonu + izin takibi).
    @Environment(\.scenePhase) private var scenePhase

    private let dependencies: any Dependencies
    @State private var coordinator: AppCoordinator

    init() {
        // SS-100 kazanç-hızı monitörü kompozisyon kökünde BİR KEZ kurulur; AYNI örnek hem
        // `FraudSignalInterceptor`'a raporlayıcı (LiveDependencies) hem `WalletStore`'a recorder
        // (AppComposition) olarak enjekte edilir → cüzdan earned-kese artışları interceptor'ın
        // gördüğü kazanç-hızı sinyalini besler. Danışma; bakiye mutasyonu yok, karar backend'de.
        let velocityMonitor = EarningVelocityMonitor()
        let dependencies = LiveDependencies(velocityReporter: velocityMonitor)
        self.dependencies = dependencies
        // Canlı feature servisleri + port adaptörleri BİR KEZ burada kurulur (03 §5). Disk store
        // kurulamıyorsa uygulama çalışamaz (SwiftData zorunlu) → kompozisyon kökü hatası ölümcüldür.
        let composition: AppComposition
        do {
            composition = try AppComposition(dependencies: dependencies, earnVelocityRecorder: velocityMonitor)
        } catch {
            fatalError("Kompozisyon kökü kurulamadı (PersistenceStore): \(error)")
        }
        _coordinator = State(initialValue: AppCoordinator(dependencies: dependencies, composition: composition))
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark) // kanon §2: dark-locked
                .onOpenURL { coordinator.open($0) } // SS-142: sıcak açılış deep link
                .task {
                    // SS-140: AppDelegate'i kompozisyon köküne bağla (tamponlanan APNs token / soğuk
                    // açılış push'u boşalır) ve açılış token/izin senkronunu yap.
                    appDelegate.pushService = coordinator.pushService
                    await coordinator.pushService.refreshRegistration()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await coordinator.pushService.refreshRegistration() }
                    }
                }
        }
    }

    /// Launch routing (03 §3.1): `Splash → Onboarding | Tabs`. Durum makinesi `LaunchCoordinator`'da;
    /// bu görünüm yalnız aktif durumu çizer. Splash arka planda ön-yükleme yapar (SS-060), onboarding
    /// tamamlanınca durum `.tabs`'e geçer ve doğrudan video ile açılan Ana Sayfa gösterilir.
    @ViewBuilder
    private var rootView: some View {
        switch coordinator.launch.launchState {
        case .splash:
            SplashView(launch: coordinator.launch)
        case .onboarding:
            if let model = coordinator.launch.onboardingModel {
                OnboardingView(model: model) // SS-064
            } else {
                SplashView(launch: coordinator.launch) // teorik olarak ulaşılmaz güvenli fallback
            }
        case .tabs:
            RootTabView(app: coordinator)
        }
    }
}
