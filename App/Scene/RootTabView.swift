import DesignSystem
import DiscoverKit
import LibraryKit
import PlayerKit
import ProfileKit
import RewardsKit
import SwiftUI

/// TabView kökü (03 §3.1): `TabCoordinator` sekme seçiminin sahibidir. 5 kanonik sekme gerçek feature
/// root view'larıyla bağlanır (F1, SS-061); her sekme kendi `NavigationStack`'ine sahiptir (02 §1.1
/// kural 4). Çapraz WalletFlow ve paylaşım sheet'leri kök seviyede tek noktadan sunulur.
struct RootTabView: View {
    @Bindable var app: AppCoordinator

    var body: some View {
        TabView(selection: tabSelection) {
            HomeTabView(coordinator: app.tabCoordinator.home)
                .tabItem { Label("Ana Sayfa", systemImage: "play.rectangle.fill") }
                .tag(TabCoordinator.Tab.anaSayfa)

            DiscoverTabView(coordinator: app.tabCoordinator.discover)
                .tabItem { Label("Keşfet", systemImage: "square.grid.2x2.fill") }
                .tag(TabCoordinator.Tab.kesfet)

            RewardsTabView(coordinator: app.tabCoordinator.rewards)
                .tabItem { Label("Ödüller", systemImage: "gift.fill") }
                .tag(TabCoordinator.Tab.oduller)

            LibraryTabView(coordinator: app.tabCoordinator.library)
                .tabItem { Label("Listem", systemImage: "bookmark.fill") }
                .tag(TabCoordinator.Tab.listem)

            ProfileTabView(coordinator: app.tabCoordinator.profile)
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                .tag(TabCoordinator.Tab.profil)
        }
        .tint(DSColors.accent)
        .walletFlow(app.tabCoordinator.walletFlow)
        .shareSheet(app.tabCoordinator.sharePresenter)
    }

    private var tabSelection: Binding<TabCoordinator.Tab> {
        Binding(
            get: { app.tabCoordinator.selectedTab },
            set: { app.tabCoordinator.select($0) }
        )
    }
}

// MARK: - Ana Sayfa (PlayerFeed + SS-065 devam et yüzeyi)

private struct HomeTabView: View {
    @Bindable var coordinator: HomeCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ZStack(alignment: .top) {
                coordinator.makePlayerFeedView()
                    .ignoresSafeArea()
                    // Bekleyen bağlamsal oynatmayı tüket: ilk mount (cold-start deep link) `.task`,
                    // sıcak sekme geçişinde gelen yeni intent `.onChange` ile feed'e seed edilir.
                    // Metot içeride guard'lıdır (pending yoksa no-op) → koşulsuz çağrılabilir.
                    .task { coordinator.seedFeedWithPendingPlaybackIfNeeded() }
                    .onChange(of: coordinator.pendingPlayback) { _, _ in
                        coordinator.seedFeedWithPendingPlaybackIfNeeded()
                    }
                    // Seed çözülünce (feedMountToken artar) PlayerFeedView yeni `entry` ile REMOUNT olur:
                    // PlayerKit seed'i yalnız init/ilk aktivasyonda tüketir → canlı VC'ye enjekte edilemez.
                    // Havuz koordinatörde yaşadığından remount player'ları korur (teardown keepPlayers).
                    .id(coordinator.feedMountToken)
                if let entry = coordinator.continueEntry.item {
                    ContinueWatchingBanner(entry: entry) { coordinator.resumeContinue(entry) }
                        .padding(.horizontal, DSSpacing.l)
                        .padding(.top, DSSpacing.s)
                }
            }
            .navigationDestination(for: AppRoute.self) { coordinator.destination(for: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .task { await coordinator.continueEntry.load() }
        }
    }
}

// MARK: - Keşfet (Kesfet → Arama → DiziDetay)

private struct DiscoverTabView: View {
    @Bindable var coordinator: DiscoverCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            KesfetView(model: coordinator.kesfetModel)
                .navigationDestination(for: AppRoute.self) { coordinator.destination(for: $0) }
        }
    }
}

// MARK: - Ödüller (OdulMerkezi)

private struct RewardsTabView: View {
    let coordinator: RewardsCoordinator

    var body: some View {
        OdulMerkeziView(model: coordinator.odulMerkeziModel)
    }
}

// MARK: - Listem (Favoriler / Devam Et → DiziDetay)

private struct LibraryTabView: View {
    @Bindable var coordinator: LibraryCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ListemView(model: coordinator.listemModel)
                .navigationDestination(for: AppRoute.self) { coordinator.destination(for: $0) }
        }
    }
}

// MARK: - Profil (Profil → Ayarlar + hesap bağlama/silme sheet'leri)

private struct ProfileTabView: View {
    @Bindable var coordinator: ProfileCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ProfilView(model: coordinator.profilModel)
                .navigationDestination(for: AppRoute.self) { coordinator.destination(for: $0) }
        }
        .sheet(isPresented: baglamaBinding) {
            if let model = coordinator.hesapBaglamaModel {
                HesapBaglamaView(model: model)
            }
        }
        .sheet(isPresented: silmeBinding) {
            if let model = coordinator.hesapSilmeModel {
                HesapSilmeView(model: model)
            }
        }
    }

    private var baglamaBinding: Binding<Bool> {
        Binding(
            get: { coordinator.hesapBaglamaModel != nil },
            set: {
                if !$0 {
                    coordinator.hesapBaglamaRequestsDismiss()
                }
            }
        )
    }

    private var silmeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.hesapSilmeModel != nil },
            set: {
                if !$0 {
                    coordinator.hesapSilmeRequestsDismiss()
                }
            }
        )
    }
}

// MARK: - SS-065 "kaldığın yerden devam et" giriş yüzeyi

private struct ContinueWatchingBanner: View {
    let entry: ContinueWatchingEntryModel.Entry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: "play.circle.fill")
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Kaldığın yerden devam et")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                    Text(verbatim: entry.title)
                        .font(DSTypography.bodyEmphasized)
                        .foregroundStyle(DSColors.textPrimary)
                        .lineLimit(1)
                    DSProgressBar(progress: entry.progressFraction)
                }
                Spacer(minLength: DSSpacing.s)
                Text(verbatim: "%\(entry.progressPercent)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textTertiary)
            }
            .padding(DSSpacing.m)
            .background(DSColors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: DSRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kaldığın yerden devam et: \(entry.title), %\(entry.progressPercent)")
    }
}
