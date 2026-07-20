import AppFoundation
import ProfileKit

/// Hesap bağlama / değişim / silme port fabrikaları (SS-132, 05 §4.2/§3.3). AppComposition.swift'ten
/// ayrılmış canlı fabrikalar: ProfileKit hesap portlarını `APIClient` + canlı `SessionManager` ve
/// (409 "mevcut hesabıma geç" için) yerel-veri yaşam döngüsü orkestratörüne bağlar.
///
/// R1 istisnası: App kompozisyon köküdür ve tüm feature modüllerini import edebilir.
@MainActor
extension AppComposition {
    /// ProfileKit hesap-bağlama servisi → `APIClient` + canlı `SessionManager` (linkSession hook'u
    /// oturumu `.linked`e yükseltir + Keychain'e yazar). 409 "mevcut hesabıma geç" için yerel-veri
    /// yaşam döngüsü orkestratörü (flush→switch→reset→refetch, 05 §3.3/§575) enjekte edilir.
    var accountLinkingService: any AccountLinkingServicing {
        APIAccountLinkingService(
            client: dependencies.apiClient,
            session: dependencies.session,
            switchDataCoordinator: accountSwitchDataCoordinator
        )
    }

    /// Hesap değişiminde (05 §3.3) yerel store yaşam döngüsü → tek-kaynak servisler + `PersistenceStore`
    /// repository'leri. `makeX` fabrikaları tür başına AYNI örneği döndürür (bulgu #9) → reset,
    /// servislerin sardığı gerçek store'u siler.
    var accountSwitchDataCoordinator: any AccountSwitchDataCoordinating {
        LiveAccountSwitchDataCoordinator(
            continueWatching: continueWatchingService,
            favorites: favoritesService,
            watchHistoryRepository: persistence.makeWatchHistoryRepository(),
            favoritesRepository: persistence.makeFavoritesRepository()
        )
    }

    /// ProfileKit hesap-silme + veri-indirme servisi → `APIClient`.
    var accountDeletionService: any AccountDeletionServicing {
        APIAccountDeletionService(client: dependencies.apiClient)
    }
}
