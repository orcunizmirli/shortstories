import AppFoundation
import ContentKit
import DiscoverKit
import PlayerKit
import WalletKit

/// Faz 2 sekme/koordinatör ekran-modeli fabrikaları (03 §5): kompozisyon kökündeki canlı port ve
/// servisleri, feature model'lerine init-injection ile bağlar. AppComposition.swift'teki Rewards/
/// Listem/Profil/Ayarlar/Hesap fabrikalarının Discover/Player/Wallet karşılığı; delegate'i çağıran
/// koordinatör geçirir, portlar burada seçilir (interface segregation).
///
/// R1 istisnası: App kompozisyon köküdür ve tüm feature modüllerini import edebilir.
@MainActor
extension AppComposition {
    // MARK: - PlayerKit (Ana Sayfa)

    /// Ana Sayfa feed durum sahibi. F1'de boş başlar; SS-062 App tarafı feed sayfalarını buraya akıtır.
    func makePlayerFeedViewModel() -> PlayerFeedViewModel {
        PlayerFeedViewModel()
    }

    // MARK: - DiscoverKit (Keşfet)

    /// Kesfet modeli — katalog + oturum-içi filtre kalıcılığı (session store koordinatör ömrünce yaşar).
    func makeKesfetModel(session: DiscoverSessionStore, delegate: (any KesfetDelegate)?) -> KesfetModel {
        KesfetModel(
            catalog: catalog,
            session: session,
            analytics: dependencies.analytics,
            delegate: delegate
        )
    }

    /// Arama modeli — arama servisi + son-aramalar (UserDefaults) kalıcılığı. `initialQuery` deep
    /// link `search?q=` ön-doldurma sorgusudur (02 §8.2).
    func makeAramaModel(
        delegate: (any AramaDelegate)?,
        source: AramaSource = .kesfet,
        initialQuery: String? = nil
    ) -> AramaModel {
        AramaModel(
            search: search,
            recentStore: PreferencesRecentSearchStore(preferences: dependencies.preferences),
            analytics: dependencies.analytics,
            delegate: delegate,
            source: source,
            initialQuery: initialQuery
        )
    }

    /// DiziDetay modeli — katalog + izleme geçmişi + favori köprüsü + entitlement (kilit kontrolü).
    func makeDiziDetayModel(
        seriesID: SeriesID,
        source: DiziDetaySource,
        delegate: (any DiziDetayDelegate)?
    ) -> DiziDetayModel {
        DiziDetayModel(
            seriesID: seriesID,
            source: source,
            catalog: catalog,
            history: discoverWatchHistoryReading,
            favorites: discoverFavoritesGateway,
            entitlement: walletStore,
            analytics: dependencies.analytics,
            delegate: delegate
        )
    }

    // MARK: - WalletKit sheet'leri (çapraz — WalletFlowCoordinator sunar)

    /// UnlockSheet modeli — canlı cüzdan (bakiye/entitlement yayınları + coin unlock) + SS-114 reklam-ile-aç
    /// portu (RewardsKit `RewardedAdService` köprüsü; bayrak/fill/cap/VIP/A-B satırı gizler/gösterir).
    func makeUnlockSheetModel(
        context: UnlockContext,
        delegate: (any UnlockSheetDelegate)?
    ) -> UnlockSheetModel {
        UnlockSheetModel(
            context: context,
            wallet: walletStore,
            analytics: decoratedAnalytics,
            delegate: delegate,
            rewardedAdUnlock: rewardedAdUnlock
        )
    }

    /// CoinMagazasi modeli — StoreKit katalog + satın alma + canlı bakiye.
    func makeCoinShopModel(
        source: CoinShopSource,
        delegate: (any CoinShopDelegate)?
    ) -> CoinShopModel {
        CoinShopModel(
            source: source,
            loader: coinStorefront,
            wallet: walletStore,
            purchasing: walletPurchasing,
            analytics: dependencies.analytics,
            delegate: delegate
        )
    }

    /// VIPAbonelik modeli — StoreKit abonelik planları + entitlement yansıması.
    func makeVIPSubscriptionModel(
        source: VIPSource,
        delegate: (any VIPSubscriptionDelegate)?
    ) -> VIPSubscriptionModel {
        VIPSubscriptionModel(
            source: source,
            loader: coinStorefront,
            wallet: walletStore,
            purchasing: walletPurchasing,
            analytics: dependencies.analytics,
            delegate: delegate
        )
    }
}
