import AppFoundation
import RewardsKit
import WalletKit

/// SS-114 rewarded ad grafiği — RewardsKit `RewardedAdService` orkestrasyonunu WalletKit UnlockSheet
/// portuna (`RewardedAdUnlocking`) bağlayan kompozisyon-kökü fabrikaları (`AppComposition+FeatureModels`
/// kalıbı; ana dosyanın uzunluk/tip-gövde bütçesini korur). Server-otoriter (06 §9, R6): istemci cap
/// saymaz/kredi vermez; VIP reklamsızlığı + `ads.rewarded_enabled` bayrağı + A/B kolu adaptörde uygulanır.
@MainActor
extension AppComposition {
    /// UnlockSheet "reklam izle" portu (WalletKit) → canlı `RewardedAdService`. Bayrak (`ads.rewarded_enabled`)
    /// + cap (`rewards.daily_ad_cap`) SS-024 RemoteConfig'ten, VIP canlı entitlement'ten enjekte edilir;
    /// adaptör VIP'e preload/availability'yi gizler (06 §9.5 reklamsızlık — zorunlu-reklam YOK).
    var rewardedAdUnlock: any WalletKit.RewardedAdUnlocking {
        let flags = dependencies.featureFlags
        let wallet = walletStore
        return RewardedAdUnlockingAdapter(
            service: makeRewardedAdService(),
            isVIP: { await wallet.subscriptionStatus().isVIP },
            rewardedAdsEnabled: { flags.value(for: Flags.rewardedAdsEnabled) },
            dailyCap: { flags.value(for: Flags.rewardedDailyCap) }
        )
    }

    /// RewardsKit izle→unlock orkestrasyonu: yer tutucu AdMob sağlayıcısı (net TODO) + canlı ad-unlock
    /// gateway (POST /rewards/ad-unlock) + A/B kolu; `decoratedAnalytics` (ab_variants boyutu) enjekte edilir.
    /// TODO(SS-113 prep): tek paylaşılan/preload-sürekli instance (AdMob envanteri sheet'ler arası korunmalı).
    private func makeRewardedAdService() -> RewardsKit.RewardedAdService {
        RewardedAdService(
            provider: PlaceholderRewardedAdProvider(),
            gateway: APIAdUnlockGateway(client: dependencies.apiClient),
            analytics: decoratedAnalytics,
            variant: rewardedAdVariant
        )
    }

    /// SS-154 rewarded ad A/B kolu (docs/08 E2). `exp_unlock_sheet` server atamasından çözülür; atama yoksa
    /// güvenli varsayılan (.adSecondary — reklam satırı görünür-ikincil). İlk okumada `ab_exposure` tetiklenir
    /// (yalnız reklam yüzeyi kurulurken — app launch'ta değil; exposure hijyeni).
    private var rewardedAdVariant: RewardsKit.RewardedAdVariant {
        switch experimentReading.variant(for: "exp_unlock_sheet")?.id {
        case "control": .control
        case "ad_secondary": .adSecondary
        default: .default
        }
    }
}
