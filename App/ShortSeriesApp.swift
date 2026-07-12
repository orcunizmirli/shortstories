import AppFoundation
import DesignSystem
import SwiftUI

/// Uygulama giriş noktası ve kompozisyon kökü (03 §5): canlı bağımlılıklar
/// BİR KEZ burada kurulur, EnvironmentKey köprüsüyle view ağacına verilir.
@main
struct ShortSeriesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let dependencies: any Dependencies
    @State private var coordinator: AppCoordinator

    init() {
        let dependencies = LiveDependencies()
        self.dependencies = dependencies
        _coordinator = State(initialValue: AppCoordinator(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(tabs: coordinator.tabCoordinator)
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark) // kanon §2: dark-locked
        }
    }
}

/// TabView kökü — TabCoordinator sekme seçiminin sahibidir (03 §3.1).
/// F0: her sekme DS token'larıyla placeholder; feature root view'ları F1'de bağlanır.
private struct RootTabView: View {
    @Bindable var tabs: TabCoordinator

    var body: some View {
        TabView(selection: $tabs.selectedTab) {
            TabPlaceholderView(
                title: "Ana Sayfa",
                detail: "PlayerFeed — dikey For You akışı (F1, PlayerKit)"
            )
            .tabItem { Label("Ana Sayfa", systemImage: "play.rectangle.fill") }
            .tag(TabCoordinator.Tab.anaSayfa)

            TabPlaceholderView(
                title: "Keşfet",
                detail: "Kategori rafları + Arama (F1, DiscoverKit)"
            )
            .tabItem { Label("Keşfet", systemImage: "square.grid.2x2") }
            .tag(TabCoordinator.Tab.kesfet)

            TabPlaceholderView(
                title: "Ödüller",
                detail: "OdulMerkezi — check-in, görevler (F1, RewardsKit)"
            )
            .tabItem { Label("Ödüller", systemImage: "gift") }
            .tag(TabCoordinator.Tab.oduller)

            TabPlaceholderView(
                title: "Listem",
                detail: "Favoriler + Devam Et (F1, LibraryKit)"
            )
            .tabItem { Label("Listem", systemImage: "bookmark") }
            .tag(TabCoordinator.Tab.listem)

            TabPlaceholderView(
                title: "Profil",
                detail: "Hesap, coin/VIP durumu, Ayarlar (F1, ProfileKit)"
            )
            .tabItem { Label("Profil", systemImage: "person.crop.circle") }
            .tag(TabCoordinator.Tab.profil)
        }
        .tint(DSColors.accent)
    }
}

/// F0 sekme placeholder'ı — yalnız DesignSystem token'ları kullanır (ham renk yasak, E2 lint).
private struct TabPlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            VStack(spacing: DSSpacing.m) {
                Text(title)
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.textPrimary)
                Text(detail)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(DSSpacing.xl)
        }
    }
}

#Preview {
    RootTabView(tabs: TabCoordinator())
        .preferredColorScheme(.dark)
}
