import AppFoundation
import PlayerKit
import WalletKit

// MARK: - Feed reaktivasyonu (SS-050/062: kilit açıldığında feed'de bölümü oynatılabilir işaretle)

extension HomeCoordinator {
    /// Bölüm kilidi açıldı (coin/reklam/başka-cihaz VIP) → feed'de o bölümü oynatılabilir işaretle. Yeni
    /// `feedState` PlayerKit'e diff'li akar; `apply(state:)` kilitli kartı YERİNDE reactivate eder (04 §9.2).
    /// `feedMountToken` BİLİNÇLİ artırılmaz (remount değil diff'li apply → korunan kare kaybolmaz). Karar
    /// SAF (`FeedUnlockReducer`): bölüm feed'de yoksa / zaten oynatılabilirse feed'e dokunulmaz.
    func applyUnlock(_ episodeID: EpisodeID) {
        guard let updatedItems = FeedUnlockReducer.applyingUnlock(
            of: episodeID,
            to: feedViewModel.feedState.items
        ) else { return }
        feedViewModel.feedState = FeedState(items: updatedItems)
        // Bu yol YALNIZ bireysel (coin/reklam) unlock'a gelir — VIP-türevli sheet tamamlanması artık App'te VIP
        // yoluna (applyVIPUnlock, REVOCABLE) yönlenir (integration-hunt fix, unlockSheetDidUnlock viaVIP). Bireysel
        // unlock KALICI (coin+reklam ikisi de WalletStore.unlockedEpisodes'ta → hasAccess true) → VIP-REVOCABLE
        // setinden ÇIKAR: izlenirse re-verify hasAccess=true bulup dokunmaz ama izlemeye gerek yok (kalıcı, tek-seferlik).
        vipGrantedEpisodes.remove(episodeID)
    }

    /// VIP aktivasyonu → feed'deki TÜM kilitli bölümleri oynatılabilir işaretle (diff'li apply, remount YOK;
    /// değişiklik yoksa dokunma). Standalone VIP feed'i reaktive etmiyordu (audit LOW; per-episode
    /// `applyUnlock` yalnız tek bölüm açardı, VIP tüm erişim verir).
    func applyVIPUnlock() {
        // İşaretlenecek bölümler applyingVIPUnlock'la AYNI yüklem (!isPlayableWithoutUnlock) → izleme kümesine ekle.
        let markedIDs = feedViewModel.feedState.items.compactMap { item -> EpisodeID? in
            guard let episode = item.episode, !episode.access.isPlayableWithoutUnlock else { return nil }
            return episode.id
        }
        guard let updatedItems = FeedUnlockReducer.applyingVIPUnlock(to: feedViewModel.feedState.items) else { return }
        feedViewModel.feedState = FeedState(items: updatedItems)
        vipGrantedEpisodes.formUnion(markedIDs) // #4: VIP'in açtığı bölümler REVOCABLE → düşüşte yeniden-doğrula
    }

    /// VIP-expiry/iade IN-SESSION re-lock (#4): VIP/coin bölüm izlerken abonelik expire/iade olursa
    /// `WalletStore.hasAccess` false'a döner ama feed client-optimistik `.unlocked` işaretini KORUYORDU →
    /// `PlayerPool.isPlayable` `.unlocked`'a güvenip hasAccess'i SORMAYIP paywall'u bypass ediyordu. Gözlemci
    /// entitlement-DÜŞÜŞÜNDE izlenenleri yeniden-doğrular + erişimi kalmayanı `.locked`'a döndürür (app-ömrü,
    /// `[weak self]`, `accountObserver` deseni; replay-on-subscribe ilk emisyon izleme boşken no-op).
    func startObservingEntitlementRevocation() {
        let changes = WalletGatewayEntitlementChangeObserving(gateway: composition.walletStore)
        entitlementObserver = Task { [weak self] in
            for await _ in changes.entitlementChanges() {
                guard let self else { return }
                await revertRevokedOptimisticUnlocks(entitlement: composition.walletStore)
            }
        }
    }

    /// #4 re-lock: VIP-grant ile işaretli bölümlerden entitlement'i KALMAYANLARI (`hasAccess` false → VIP-expiry)
    /// feed'de geri `.locked` yapar. Bireysel coin/reklam unlock KALICI (izlenmez) + katalog-historik `.unlocked`
    /// izlenmez → dokunulmaz (false-lock yok). `await hasAccess` sırasında hesap değişimi (resetForAccountSwitch
    /// izlemeyi temizler) araya girerse revoked GÜNCEL kümeyle kesiştirilir → A'nın revoked'ı B'yi kilitlemez.
    func revertRevokedOptimisticUnlocks(entitlement: any EntitlementChecking) async {
        let tracked = vipGrantedEpisodes // snapshot: await sırasında (reset/unlock) değişebilir
        guard !tracked.isEmpty else { return }
        var revoked: Set<EpisodeID> = []
        for episodeID in tracked {
            let stillEntitled = await entitlement.hasAccess(to: episodeID)
            if !stillEntitled {
                revoked.insert(episodeID)
            }
        }
        // Cross-account fence: await sırasında resetForAccountSwitch izlemeyi temizlediyse (hesap geçişi),
        // yalnız HÂLÂ izlenen bölümlere uygula → A'nın revoked'ı B'nin feed'ini kilitlemez.
        revoked.formIntersection(vipGrantedEpisodes)
        guard !revoked.isEmpty else { return }
        if let updated = FeedUnlockReducer.revertingRevokedUnlocks(of: revoked, to: feedViewModel.feedState.items) {
            feedViewModel.feedState = FeedState(items: updated)
        }
        vipGrantedEpisodes.subtract(revoked)
    }
}
