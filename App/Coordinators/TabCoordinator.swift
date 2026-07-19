import AppFoundation
import DiscoverKit
import Foundation
import Observation

/// TabView sahibi koordinatör (03 §3.1): sekme seçimi state'i + 5 feature koordinatörü + çapraz
/// WalletFlow burada birleşir. Sekme değişimi `PlayerFeed`'e pause/resume sinyalini üretir (SS-061)
/// ve deep link'leri hedef sekme koordinatörüne delege eder (SS-142, 02 §8.4).
@Observable
@MainActor
final class TabCoordinator {
    /// Kanonik 5 sekme (kanon §3). Varsayılan `anaSayfa` — uygulama doğrudan video ile açılır.
    enum Tab: Hashable, CaseIterable {
        case anaSayfa
        case kesfet
        case oduller
        case listem
        case profil
    }

    private(set) var selectedTab: Tab = .anaSayfa
    /// Sekme geçiş analitiği + geri-dönüş kararları için önceki sekme (SS-061 `tab_selected.previous_tab`).
    private(set) var previousTab: Tab = .anaSayfa

    // MARK: - Alt koordinatörler (03 §3.1 hiyerarşisi)

    let walletFlow: WalletFlowCoordinator
    let home: HomeCoordinator
    let discover: DiscoverCoordinator
    let rewards: RewardsCoordinator
    let library: LibraryCoordinator
    let profile: ProfileCoordinator

    /// Kök seviye paylaşım sunumu (SS-063/083): DiziDetay/Listem/PlayerFeed paylaşım niyetleri buraya
    /// akar; `RootTabView` tek `.shareSheet` ile sunar (hangi sekmede olursa olsun çalışır).
    let sharePresenter = SharePresenter()

    /// Deep link çözüm analitiği için kompozisyon-kökü tracker'ı (02 §8.4 kural 5 `deeplink_opened`).
    private let analytics: any AnalyticsTracking

    init(composition: AppComposition) {
        analytics = composition.dependencies.analytics
        let walletFlow = WalletFlowCoordinator(composition: composition)
        self.walletFlow = walletFlow
        home = HomeCoordinator(composition: composition, walletFlow: walletFlow)
        discover = DiscoverCoordinator(composition: composition, walletFlow: walletFlow)
        rewards = RewardsCoordinator(composition: composition, walletFlow: walletFlow)
        library = LibraryCoordinator(composition: composition, walletFlow: walletFlow)
        profile = ProfileCoordinator(composition: composition, walletFlow: walletFlow)

        // Cross-tab geçiş için zayıf geri-referanslar (döngü yok; TabCoordinator hepsinin sahibidir).
        home.tabCoordinator = self
        discover.tabCoordinator = self
        library.tabCoordinator = self
        profile.tabCoordinator = self
    }

    // MARK: - Sekme geçişi (03 §3.2 kural 4)

    /// Hedef sekmeye geçer; önceki sekmeyi kaydeder ve Ana Sayfa pause/resume sinyalini üretir.
    /// `action` geçiş sonrası hedef koordinatöre rota uygulamak içindir (ör. segment/filtre).
    func switchTab(_ tab: Tab, then action: (() -> Void)? = nil) {
        guard tab != selectedTab else {
            action?()
            return
        }
        previousTab = selectedTab
        selectedTab = tab
        signalPlaybackActivity()
        // TODO(SS-061 analitik): `tab_selected {tab, previous_tab}` — event registry'ye (08 §2) eklenip
        // canlı tracker'a atılacak († — şimdi atmak strict-debug assertion'ı tetikler).
        action?()
    }

    /// SwiftUI `TabView` selection binding'i buradan geçer (aynı-sekme değerinde no-op).
    func select(_ tab: Tab) {
        switchTab(tab)
    }

    /// Ana Sayfa'dan ayrılınca pause, dönünce resume sinyali (SS-061). Pause fiilen
    /// `PlayerFeedViewController.viewWillDisappear`'da; bu sinyal resume kancasını da hazırlar.
    private func signalPlaybackActivity() {
        home.setActive(selectedTab == .anaSayfa)
    }

    // MARK: - Bağlamsal oynatma funnel'ı (Listem/DiziDetay/Profil → PlayerFeed)

    func requestPlayback(_ intent: HomeCoordinator.PlaybackIntent) {
        switchTab(.anaSayfa)
        home.requestPlayback(intent)
    }

    // MARK: - Deep link yönlendirme (SS-142, 02 §8.4)

    // Düz `Route` dağıtım tablosu (her case tek satır delege) — döngüsel karmaşıklık doğası gereği
    // case sayısı kadardır; tek switch olması dağıtımın tam listesini bir yerde tutar.
    // swiftlint:disable cyclomatic_complexity

    /// Çözülmüş rotayı hedef sekme koordinatörüne delege eder. AppCoordinator soğuk açılış
    /// `PendingRoute`'unu (ve banner/kampanya rotalarını) buraya akıtır; `source` başarılı çözüm
    /// analitiğini besler (02 §8.4 kural 5). `source` verilmezse iç navigasyon kabul edilir.
    func handle(_ route: DeepLinkRoute, source: DeepLinkSource = .appInternal) {
        // 02 §8.4 kural 5: her başarılı çözüm `deeplink_opened {route_type, source}` atar. Kayıt
        // AnalyticsEventRegistry'de olduğundan fault üretmez (campaign_id F1'de yok — opsiyonel).
        analytics.track("deeplink_opened", parameters: [
            "route_type": .string(route.analyticsType),
            "source": .string(source.rawValue)
        ])
        switch route {
        case .home:
            switchTab(.anaSayfa)
        case let .play(seriesId, startSeconds):
            requestPlayback(HomeCoordinator.PlaybackIntent(
                seriesID: seriesId,
                episodeNumber: nil,
                startPositionSec: Double(startSeconds ?? 0)
            ))
        case let .series(id):
            switchTab(.kesfet)
            discover.showDetail(id, source: .deeplink)
        case let .episode(seriesId, number):
            // 02 §8.2/§5.6: bölüm hedefi DiziDetay DEĞİL, Ana Sayfa PlayerFeed'in bağlamsal
            // konumlanmasıdır (bölüm açıksa oynar, kilitliyse kart + UnlockSheet). Bölüm numarası
            // taşınır; deep link pozisyon içermez (başlangıç 0 — `play?t=` devam-et içindir).
            requestPlayback(HomeCoordinator.PlaybackIntent(
                seriesID: seriesId,
                episodeNumber: number,
                startPositionSec: 0
            ))
        case let .discover(genre):
            switchTab(.kesfet)
            discover.applyGenre(genre)
        case let .search(query):
            switchTab(.kesfet)
            discover.showSearch(query: query)
        case let .rewards(anchor):
            switchTab(.oduller)
            // TODO(SS-111): anchor == .checkin → OdulMerkezi check-in şeridine scroll + vurgu.
            // RewardsKit'te public çapa girişi yok (feature dilimi bağlanınca).
            _ = anchor
        case let .coinStore(offer):
            // TODO(SS-095): offer → ilk-yükleme teklifi vurgusu (CoinShopModel init param'ı yok).
            _ = offer
            walletFlow.presentCoinStore(source: .deeplink)
        case let .vip(preselectedPlan):
            // TODO(SS-096): preselectedPlan → VIPAbonelik plan ön-seçimi (VIPSubscriptionModel yok).
            _ = preselectedPlan
            walletFlow.presentVIP(source: .deeplink)
        case let .myList(segment):
            switchTab(.listem)
            library.selectSegment(segment)
        case .profile:
            switchTab(.profil)
        case let .settings(section):
            switchTab(.profil)
            // TODO(SS-130): section → Ayarlar alt-bölümüne scroll (AyarlarModel çapa girişi yok).
            _ = section
            profile.showSettings()
        case .notifications:
            // SS-144: `shortseries://notifications` (deep-link) + push tap ikisi de Profil sekmesine
            // geçip BildirimMerkezi'ni Profil stack'inde iter (02 §4.15/§8.2). Atıf yukarıda
            // `deeplink_opened {route_type: "notifications", source}` ile atıldı.
            switchTab(.profil)
            profile.showNotificationCenter()
        }
    }

    // swiftlint:enable cyclomatic_complexity
}

// MARK: - DiziDetayDelegate (02 §4.4) — stack-bağımsız, tüm sekmelerin DiziDetay'ı buraya bağlanır

extension TabCoordinator: DiziDetayDelegate {
    func diziDetayStartWatching(seriesID: SeriesID, episodeNumber: Int, startPositionSec: Double) {
        // "İzlemeye Başla / Devam Et" → Ana Sayfa bağlamsal player (SS-062 App feed dilimi tüketir).
        requestPlayback(HomeCoordinator.PlaybackIntent(
            seriesID: seriesID,
            episodeNumber: episodeNumber,
            startPositionSec: startPositionSec
        ))
    }

    func diziDetayRequestsUnlock(_ intent: LockedEpisodeIntent) {
        walletFlow.presentUnlock(intent: intent, source: .diziDetay)
    }

    func diziDetayShare(_ url: URL) {
        sharePresenter.share(url)
    }

    func diziDetayRequestsDiscover(genre: String) {
        switchTab(.kesfet)
        discover.applyGenre(genre)
    }
}
