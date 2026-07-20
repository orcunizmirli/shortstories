import Foundation
import Testing
@testable import RewardsKit

/// SS-113 SAF görünürlük kararı (06 §9.2/§9.5): matris flag × fill × cap. Server-otoriter cap
/// (05 §963: istemci saymaz — `remaining` server'dan) ve doldurma-yok gizleme kuralları. VIP + A/B
/// kolu üst kapıları servis katmanında (bkz. `RewardedAdServiceTests`). Yan etkisiz — izole test.
@Suite("SS-113 RewardedAdAvailability saf karar")
struct RewardedAdAvailabilityTests {
    private func evaluate(
        enabled: Bool = true,
        hasFill: Bool = true,
        remaining: Int? = 3,
        resetsAt: Date? = nil
    ) -> RewardedAdAvailability {
        RewardedAdAvailability.evaluate(
            rewardedAdsEnabled: enabled,
            hasFill: hasFill,
            remaining: remaining,
            resetsAt: resetsAt
        )
    }

    // MARK: - Mutlu yol

    @Test func availableWhenEnabledFilledAndUnderCap() {
        #expect(evaluate(remaining: 3) == .available(remaining: 3))
    }

    @Test func availableCarriesServerRemainingForCounter() {
        // "Bugün 5/5" göstergesi server'ın verdiği kalan haktan gelir (05 §963).
        #expect(evaluate(remaining: 5) == .available(remaining: 5))
    }

    @Test func availableWithUnknownRemainingStaysActionable() {
        // Server kalan hakkı bildirmediyse satır etkin kalır; sayı gösterilmez (server izle-anında gate'ler).
        let result = evaluate(remaining: nil)
        #expect(result == .available(remaining: nil))
        #expect(result.isActionable)
    }

    // MARK: - Ana şalter (SS-024 remote flag) — gizle

    @Test func hiddenWhenFlagDisabled() {
        #expect(evaluate(enabled: false) == .hidden)
    }

    @Test func flagDisabledBeatsCap() {
        // Flag kapalıysa cap değerinden bağımsız daima gizli (server degrade kapısı).
        #expect(evaluate(enabled: false, remaining: 0) == .hidden)
    }

    // MARK: - Doldurma yok (06 §9.5) — KART GİZLENİR

    @Test func hiddenWhenNoFill() {
        #expect(evaluate(hasFill: false, remaining: 3) == .hidden)
    }

    // MARK: - Cap doldu (server remaining <= 0) — görünür ama DEVRE DIŞI

    @Test func capReachedWhenServerRemainingZero() {
        let resets = Date(timeIntervalSince1970: 1_000_000)
        let result = evaluate(remaining: 0, resetsAt: resets)
        #expect(result == .capReached(resetsAt: resets))
        #expect(result.isVisible)
        #expect(result.isActionable == false)
    }

    @Test func capReachedTreatsNegativeRemainingAsCap() {
        #expect(evaluate(remaining: -1) == .capReached(resetsAt: nil))
    }

    @Test func capReachedIndependentOfFill() {
        // Cap sert sınırdır: doldurma olmasa bile capReached (fill'e bakılmadan; 06 §9.2 ödeme baskısı).
        #expect(evaluate(hasFill: false, remaining: 0) == .capReached(resetsAt: nil))
    }

    // MARK: - A/B varyantı (SS-154) — enum kapısı

    @Test func variantControlDisablesSurface() {
        #expect(RewardedAdVariant.control.surfaceEnabled == false)
        #expect(RewardedAdVariant.adSecondary.surfaceEnabled)
        #expect(RewardedAdVariant.default == .adSecondary)
    }
}
