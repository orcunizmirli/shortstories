import AppFoundation
import Observation

/// Uygulama yaşam döngüsü + launch routing koordinatörü (03 §3.1).
/// F0 iskeleti: doğrudan TabCoordinator'a geçer; Splash/Onboarding yönlendirmesi,
/// deep link (`PendingRoute`) çözümü ve zorunlu güncelleme/bakım overlay'leri F1'de.
@Observable @MainActor
final class AppCoordinator {
    enum LaunchState {
        case splash
        case onboarding
        case tabs
    }

    /// F0: Splash/Onboarding akışı henüz yok — sabit `.tabs`.
    private(set) var launchState: LaunchState = .tabs

    let tabCoordinator: TabCoordinator

    private let dependencies: any Dependencies

    init(dependencies: any Dependencies) {
        self.dependencies = dependencies
        tabCoordinator = TabCoordinator()
    }

    // TODO(F1): SessionState'e göre launch routing — Splash → Onboarding | Tabs (03 §3.1).
    // TODO(F1): deep link çözümü — shortseries://series/{seriesId}/episode/{n};
    //           soğuk açılışta PendingRoute saklanır (03 §3.2 kural 6).
}
