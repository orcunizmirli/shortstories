import AppFoundation
import Testing
@testable import WalletKit

/// Para etkili POST uçları (03 §8.3 + RetryPolicy tablosu "Cüzdan/satın alma uçları | .never"):
/// `/iap/verify` ve `/wallet/unlock` OTOMATİK retry ALMAZ. Kurtarma StoreKit unfinished
/// kuyruğu (verify) / kullanıcı-tetikli yeniden deneme (unlock) ile yapılır — çift-kredi/çift-harcama
/// yarış penceresi daraltılır.
struct WalletEndpointsTests {
    @Test func verifyEndpointRetryYok() {
        let endpoint = VerifyEndpoint(productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, key: "k1")
        #expect(endpoint.retryPolicy == .never)
    }

    @Test func unlockEndpointRetryYok() {
        let endpoint = UnlockEndpoint(episodeID: EpisodeID("ep_1"), expectedPrice: 60, key: "k1")
        #expect(endpoint.retryPolicy == .never)
    }

    /// Regresyon guard: para etkili OLMAYAN GET uçları hâlâ default retry alır (03 §8.3).
    @Test func walletBalanceEndpointDefaultRetry() {
        #expect(WalletBalanceEndpoint().retryPolicy == .default)
    }

    @Test func subscriptionEndpointDefaultRetry() {
        #expect(SubscriptionEndpoint().retryPolicy == .default)
    }
}
