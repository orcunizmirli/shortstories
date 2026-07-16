import AppFoundation
import DesignSystem
import SwiftUI

/// Uygulama giriş noktası ve kompozisyon kökü (03 §5): canlı bağımlılıklar
/// BİR KEZ burada kurulur, `AppCoordinator`/`TabCoordinator` hiyerarşisi buradan sürer.
@main
struct ShortSeriesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let dependencies: any Dependencies
    @State private var coordinator: AppCoordinator

    init() {
        let dependencies = LiveDependencies()
        self.dependencies = dependencies
        // Canlı feature servisleri + port adaptörleri BİR KEZ burada kurulur (03 §5). Disk store
        // kurulamıyorsa uygulama çalışamaz (SwiftData zorunlu) → kompozisyon kökü hatası ölümcüldür.
        let composition: AppComposition
        do {
            composition = try AppComposition(dependencies: dependencies)
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
