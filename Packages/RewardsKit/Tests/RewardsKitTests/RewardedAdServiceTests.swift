import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import RewardsKit

/// SS-113 izle→unlock orkestrasyonu (06 §9.3/§9.4). SERVER-OTORİTER: istemci cap saymaz, ödül
/// kredilemez, kilit açmaz. 30 sn tamamlama → server SSV → unlock; erken kapatma/hata/red → ödül YOK.
/// Analitik: rewarded_ad_start/complete/fail (§3.5). Mock provider + mock gateway ile izole.
@MainActor
@Suite("SS-113 RewardedAdService izle→unlock akışı")
struct RewardedAdServiceTests {
    private func makeService(
        provider: MockRewardedAdProvider = MockRewardedAdProvider(),
        gateway: MockAdUnlockGateway = MockAdUnlockGateway(),
        analytics: MockAnalytics = MockAnalytics(),
        variant: RewardedAdVariant = .adSecondary
    ) -> RewardedAdService {
        RewardedAdService(provider: provider, gateway: gateway, analytics: analytics, variant: variant)
    }

    // MARK: - Ön-yükleme

    @Test func preloadDelegatesToProvider() async {
        let provider = MockRewardedAdProvider()
        let service = makeService(provider: provider)
        await service.preload()
        #expect(provider.preloadCount == 1)
    }

    // MARK: - Görünürlük köprüsü (provider fill + saf karar)

    @Test func availabilityHiddenWhenProviderHasNoFill() async {
        let provider = MockRewardedAdProvider(fill: false)
        let service = makeService(provider: provider)
        let result = await service.availability(rewardedAdsEnabled: true, isVIP: false, remaining: 3)
        #expect(result == .hidden)
    }

    @Test func availabilityAvailableWhenFilledUnderCap() async {
        let provider = MockRewardedAdProvider(fill: true)
        let service = makeService(provider: provider)
        let result = await service.availability(rewardedAdsEnabled: true, isVIP: false, remaining: 3)
        #expect(result == .available(remaining: 3))
    }

    @Test func availabilityHiddenForVIP() async {
        let provider = MockRewardedAdProvider(fill: true)
        let service = makeService(provider: provider)
        let result = await service.availability(rewardedAdsEnabled: true, isVIP: true, remaining: 3)
        #expect(result == .hidden)
    }

    @Test func availabilityHiddenWhenVariantControlArm() async {
        // A/B kontrol kolu (SS-154): doldurma olsa bile yüzey gizli (docs/08 E2 control).
        let provider = MockRewardedAdProvider(fill: true)
        let service = makeService(provider: provider, variant: .control)
        let result = await service.availability(rewardedAdsEnabled: true, isVIP: false, remaining: 3)
        #expect(result == .hidden)
        // VIP/kontrol kolunda reklam SDK'sı YOKLANMAZ (fill sorgusu atlanır).
        #expect(provider.preloadCount == 0)
    }

    @Test func availabilityCapReachedFromServerRemaining() async {
        let resets = Date(timeIntervalSince1970: 2_000_000)
        let service = makeService()
        let result = await service.availability(
            rewardedAdsEnabled: true, isVIP: false, remaining: 0, resetsAt: resets
        )
        #expect(result == .capReached(resetsAt: resets))
    }

    // MARK: - 30 sn tamamlama → server SSV → unlock (server-otoriter)

    @Test func completedWatchUnlocksViaServer() async {
        let provider = MockRewardedAdProvider(outcome: .completed(.mock(nonce: "adn_777")))
        let gateway = MockAdUnlockGateway(.success(.mock(target: .episode(id: "ep_9"), remainingToday: 2)))
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_9"), placement: .unlockSheet)

        #expect(result == .unlocked(.mock(target: .episode(id: "ep_9"), remainingToday: 2)))
        #expect(provider.showCount == 1)
        // Gateway sağlayıcı-bağımsız kanıt zarfını + doğru hedefi aldı.
        #expect(gateway.requestCount == 1)
        #expect(gateway.lastRequest?.target == .episode(id: "ep_9"))
        #expect(gateway.lastRequest?.proof.nonce == "adn_777")
        #expect(gateway.lastRequest?.proof.provider == "admob")
    }

    @Test func completedWatchForCoinRewardTarget() async {
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.success(.mock(target: .coinReward, remainingToday: 1, coinBalance: 130)))
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .coinReward, placement: .odulMerkezi)

        #expect(result == .unlocked(.mock(target: .coinReward, remainingToday: 1, coinBalance: 130)))
        #expect(gateway.lastRequest?.target == .coinReward)
    }

    // MARK: - Erken kapatma → ödül YOK, gateway çağrılMAZ, hak düşmez (06 §9.3)

    @Test func dismissedEarlyGivesNoReward() async {
        let provider = MockRewardedAdProvider(outcome: .dismissedEarly)
        let gateway = MockAdUnlockGateway()
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .dismissedEarly)
        #expect(gateway.requestCount == 0) // server'a HİÇ istek gitmez (kredi yok)
    }

    // MARK: - Doldurma yok / gösterim hatası → ödül YOK, gateway çağrılMAZ

    @Test func noFillGivesNoReward() async {
        let provider = MockRewardedAdProvider(outcome: .noFill)
        let gateway = MockAdUnlockGateway()
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .noFill)
        #expect(gateway.requestCount == 0)
    }

    @Test func showFailureGivesNoReward() async {
        let provider = MockRewardedAdProvider(outcome: .failed)
        let gateway = MockAdUnlockGateway()
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .failed)
        #expect(gateway.requestCount == 0)
    }

    // MARK: - Server cap aşımı (429) → görünür-devre dışı, ödül YOK

    @Test func serverCapReachedYieldsCapReached() async {
        let resets = Date(timeIntervalSince1970: 3_000_000)
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.failure(AdUnlockError.capReached(resetsAt: resets)))
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .capReached(resetsAt: resets))
    }

    // MARK: - Server SSV reddi → kilit AÇILMAZ, ödül YOK (client callback'ine güvenilmez, 06 §9.4)

    @Test func serverRejectsProofYieldsNoUnlock() async {
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.failure(AdUnlockError.rewardRejected))
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .rewardRejected)
    }

    // MARK: - Transport hatası → ödül YOK (S2S callback gelirse server yine işler; snapshot çözer)

    @Test func transportErrorGivesNoReward() async {
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.failure(AppError.network(.timeout)))
        let service = makeService(provider: provider, gateway: gateway)

        let result = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(result == .failed)
    }

    // MARK: - Analitik (§3.5): start / complete / fail

    @Test func emitsStartThenCompleteOnSuccessfulUnlock() async {
        let analytics = MockAnalytics()
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.success(.mock(remainingToday: 2)))
        let service = makeService(provider: provider, gateway: gateway, analytics: analytics)

        _ = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet, dailyCap: 5)

        #expect(analytics.eventNames == ["rewarded_ad_start", "rewarded_ad_complete"])
        let complete = analytics.events.first { $0.name == "rewarded_ad_complete" }
        #expect(complete?.parameters["placement"] == .string("unlock_sheet"))
        #expect(complete?.parameters["daily_cap"] == .int(5))
        // ads_used_today = cap(5) − server remaining(2) = 3 (SERVER remaining'den türetilir, istemci saymaz).
        #expect(complete?.parameters["ads_used_today"] == .int(3))
    }

    @Test func emitsFailOnNoFill() async {
        let analytics = MockAnalytics()
        let provider = MockRewardedAdProvider(outcome: .noFill)
        let service = makeService(provider: provider, analytics: analytics)

        _ = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .odulMerkezi, dailyCap: 5)

        #expect(analytics.eventNames == ["rewarded_ad_start", "rewarded_ad_fail"])
        let fail = analytics.events.first { $0.name == "rewarded_ad_fail" }
        #expect(fail?.parameters["placement"] == .string("odul_merkezi"))
    }

    @Test func emitsFailOnServerReject() async {
        let analytics = MockAnalytics()
        let provider = MockRewardedAdProvider(outcome: .completed(.mock()))
        let gateway = MockAdUnlockGateway(.failure(AdUnlockError.rewardRejected))
        let service = makeService(provider: provider, gateway: gateway, analytics: analytics)

        _ = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(analytics.eventNames == ["rewarded_ad_start", "rewarded_ad_fail"])
    }

    @Test func earlyDismissEmitsNoFailEvent() async {
        // Erken kapatma kullanıcı seçimidir → yalnız start; fail ATILMAZ (§3.5 semantiği).
        let analytics = MockAnalytics()
        let provider = MockRewardedAdProvider(outcome: .dismissedEarly)
        let service = makeService(provider: provider, analytics: analytics)

        _ = await service.watchAdToUnlock(target: .episode(id: "ep_1"), placement: .unlockSheet)

        #expect(analytics.eventNames == ["rewarded_ad_start"])
    }

    // MARK: - A/B varyantı enjekte edilir ve okunabilir (SS-154)

    @Test func exposesInjectedVariant() {
        let service = makeService(variant: .control)
        #expect(service.abVariant == .control)
    }
}
