import Observation

/// TabView sahibi koordinatör (03 §3.1): sekme seçimi state'i buradadır.
/// F0 iskeleti: feature koordinatörleri (Home/Discover/Rewards/Library/Profile)
/// ve `PlayerFeed` pause/resume sinyali F1'de bağlanır.
@Observable @MainActor
final class TabCoordinator {

    /// Kanonik 5 sekme (kanon §3). Varsayılan `anaSayfa` — uygulama doğrudan
    /// video ile açılır.
    enum Tab: Hashable, CaseIterable {
        case anaSayfa
        case kesfet
        case oduller
        case listem
        case profil
    }

    var selectedTab: Tab = .anaSayfa

    /// Sekmeler arası geçiş API'sinin tohumu (03 §3.2 kural 4).
    /// TODO(F1): `switchTab(_:then:)` — hedef sekme koordinatörüne rota delege eder.
    func switchTab(_ tab: Tab) {
        selectedTab = tab
    }
}
