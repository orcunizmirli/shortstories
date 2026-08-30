import AppFoundation
import Foundation
import LibraryKit
import XCTest
@testable import ShortSeriesApp

/// Audit HIGH (§575 / SS-132 sınıfı cross-account sızıntı): hesap-değişiminde
/// `LiveAccountSwitchDataCoordinator` yalnız izleme-geçmişi + favori repo'larını DEĞİL, paylaşılan
/// `WalletStore`'u da sıfırlamalı (`resetLocalUserData`→resetWallet) ve yeni hesabın otoritatif
/// snapshot'ını çekmeli (`refetchForNewAccount`→refreshWallet). Aksi halde önceki hesabın
/// bakiye/VIP/açık-bölüm state'i yeni hesaba sızar (WalletStore singleton relaunch'a kadar kalıcı).
final class AccountSwitchWalletResetTests: XCTestCase {
    func testResetLocalUserDataResetsWalletNotRefresh() async {
        let spy = WalletLifecycleSpy()
        let coordinator = makeCoordinator(spy)

        await coordinator.resetLocalUserData()

        let resets = await spy.resetCount
        let refreshes = await spy.refreshCount
        XCTAssertEqual(resets, 1) // cüzdan state'i sıfırlandı (bakiye/VIP/açık-bölüm sızmaz)
        XCTAssertEqual(refreshes, 0) // reset yalnız temizler, çekmez
    }

    func testRefetchForNewAccountRefreshesWallet() async {
        let spy = WalletLifecycleSpy()
        let coordinator = makeCoordinator(spy)

        await coordinator.refetchForNewAccount()

        let refreshes = await spy.refreshCount
        XCTAssertEqual(refreshes, 1) // yeni hesabın otoritatif cüzdan snapshot'ı çekildi
    }

    private func makeCoordinator(_ spy: WalletLifecycleSpy) -> LiveAccountSwitchDataCoordinator {
        let watchRepo = NoopWatchHistoryRepository()
        let favRepo = NoopFavoritesRepository()
        return LiveAccountSwitchDataCoordinator(
            continueWatching: ContinueWatchingService(repository: watchRepo, remoting: NoopWatchProgressRemoting()),
            favorites: FavoritesService(repository: favRepo, remoting: NoopFavoritesRemoting()),
            watchHistoryRepository: watchRepo,
            favoritesRepository: favRepo,
            resetWallet: { await spy.recordReset() },
            refreshWallet: { await spy.recordRefresh() }
        )
    }
}

// MARK: - Test doubles (yerel; AppTests AppFoundationTestSupport'u linklemez)

private actor WalletLifecycleSpy {
    private(set) var resetCount = 0
    private(set) var refreshCount = 0
    func recordReset() {
        resetCount += 1
    }

    func recordRefresh() {
        refreshCount += 1
    }
}

private struct NoopWatchHistoryRepository: WatchHistoryRepository {
    func saveProgress(_: WatchProgressRecord) async throws {}
    func mergeServerProgress(_: [WatchProgressRecord]) async throws {}
    func progress(forEpisode _: EpisodeID) async throws -> WatchProgressRecord? {
        nil
    }

    func progress(forSeries _: SeriesID) async throws -> [WatchProgressRecord] {
        []
    }

    func latestProgress(forSeries _: SeriesID) async throws -> WatchProgressRecord? {
        nil
    }

    func continueWatching(limit _: Int) async throws -> [WatchProgressRecord] {
        []
    }

    func pendingUploads() async throws -> [WatchProgressRecord] {
        []
    }

    func markSynced(uploaded _: [WatchProgressRecord]) async throws {}
    func deleteAll() async throws {}
}

private struct NoopFavoritesRepository: FavoritesRepository {
    func isFavorite(_: SeriesID) async throws -> Bool {
        false
    }

    func favorites() async throws -> [FavoriteRecord] {
        []
    }

    func addFavorite(_: SeriesID, at _: Date) async throws {}
    func removeFavorite(_: SeriesID) async throws {}
    func removeFavorites(_: Set<SeriesID>) async throws {}
    func toggleFavorite(_: SeriesID, at _: Date) async throws -> Bool {
        false
    }

    func pendingSync() async throws -> [PendingFavoriteSync] {
        []
    }

    func confirmAdd(_: SeriesID) async throws {}
    func confirmRemoval(_: SeriesID) async throws {}
    func rollbackAdd(_: SeriesID) async throws {}
    func rollbackRemoval(_: SeriesID) async throws {}
    func deleteAll() async throws {}
}

private struct NoopWatchProgressRemoting: WatchProgressRemoting {
    func uploadProgress(_: [WatchProgressRecord]) async throws {}
    func fetchServerProgress() async throws -> [WatchProgressRecord] {
        []
    }
}

private struct NoopFavoritesRemoting: FavoritesRemoting {
    func putFavorite(_: SeriesID) async throws {}
    func deleteFavorite(_: SeriesID) async throws {}
}
