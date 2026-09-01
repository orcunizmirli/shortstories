import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import RewardsKit

/// SS-110/111 `OdulMerkeziModel` check-in yarış düzeltmesi: uçuştaki `status()` tazelemesi, await
/// sırasında araya giren bir `claim()`'in TAZE state'ini EZMEMELİ (generation guard). Aksi halde bayat
/// pre-claim status SAHTE `checkin_streak_break` atar ve claim butonunu geri açar (08 §3.5 KPI + UX).
@MainActor
@Suite("OdulMerkezi check-in tazeleme yarışı (generation guard)")
struct OdulMerkeziCheckInRaceTests {
    @Test func inFlightStatusRefreshDoesNotOverwriteFreshClaimState() async {
        let claimed = CheckInClaimResult.mock(
            coins: 20,
            coinBalance: 120,
            checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4)
        )
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3), // BAYAT pre-claim state
            claim: claimed
        )
        let analytics = MockAnalytics()
        let model = OdulMerkeziModel(
            checkInService: service,
            wallet: FakeRewardsWallet(100),
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: analytics,
            featureFlags: MockFeatureFlags(),
            delegate: RewardsDelegateSpy()
        )
        model.onAppear()
        await model.pendingWork() // ilk yükleme: streak 3, todayClaimed false, loadState .loaded
        #expect(model.streakDays == 3)

        // Gate'i kur → sonraki status() (tazeleme) BLOKLANIR; base status BAYAT (streak 3) kalır.
        service.arm()
        model.onAppear() // runRefresh → refreshTasks → refreshCheckIn → status() gate'te bloklanır
        await service.gate.waitForArrival()

        // status BLOKLUYKEN claim TAMAMLANIR → checkInState streak 4, generation bump.
        await model.claimToday()
        #expect(model.streakDays == 4)
        #expect(model.checkInState?.todayClaimed == true)

        // Bayat status serbest → generation guard onu DÜŞÜRÜR (streak 3 pre-claim).
        await service.gate.release()
        await model.pendingWork()

        #expect(model.streakDays == 4) // bayat streak 3 düşürüldü
        #expect(model.checkInState?.todayClaimed == true)
        #expect(model.canClaimToday == false) // buton geri AÇILMADI
        #expect(!analytics.events.contains { $0.name == "checkin_streak_break" }) // SAHTE kırılma yok
    }

    @Test func postClaimStaleRefreshDoesNotReopenClaim() async {
        // MEDIUM (RewardsKit hunt): generation-guard YALNIZ claim-anında UÇUŞTA olan status()'ü düşürür. Claim'den
        // SONRA başlayan warm refreshCheckIn post-claim generation'ı yakalar → fence GEÇER; server read-replica bayat
        // pre-claim status dönerse buton geri açılır + sahte streak_break + lastSeenStreak bozulur. Task-tarafı
        // reconcileClaimed (Fix 4) pinine simetrik: claim-pin bayat downgrade'i engeller.
        let store = InMemoryLastSeenStreakStore(nil)
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3), // server BAYAT pre-claim döner
            claim: .mock(coins: 20, coinBalance: 120, checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4))
        )
        let analytics = MockAnalytics()
        let model = OdulMerkeziModel(
            checkInService: service,
            wallet: FakeRewardsWallet(100),
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: analytics,
            featureFlags: MockFeatureFlags(),
            delegate: RewardsDelegateSpy(),
            lastSeenStreakStore: store
        )
        model.onAppear()
        await model.pendingWork() // ilk yükleme: streak 3, todayClaimed false
        await model.claimToday()
        #expect(model.streakDays == 4)
        #expect(model.checkInState?.todayClaimed == true)

        // Claim SONRASI warm refresh (in-flight DEĞİL → generation eşleşir); server hâlâ bayat pre-claim döner.
        model.onAppear()
        await model.pendingWork()

        #expect(model.streakDays == 4) // bayat streak 3 uygulanMADI (claim-pin korudu)
        #expect(model.checkInState?.todayClaimed == true)
        #expect(model.canClaimToday == false) // buton geri AÇILMADI
        #expect(store.lastSeenStreak() == 4) // lastSeenStreak 3'e BOZULMADI
        #expect(!analytics.events.contains { $0.name == "checkin_streak_break" }) // SAHTE kırılma yok
    }

    @Test func claimInFlightDuringAccountSwitchDoesNotWriteOldAccountData() async {
        // Self-review HIGH: claim UÇUŞTAYKEN resetForAccountSwitch olursa (hesap switch), A hesabının claim
        // yanıtı (bakiye/checkin/lastSeenStreak) B state'ine YAZILMAMALI (accountEpoch fence). refreshCheckIn
        // generation-guard'ı bu yolu KAPSAMIYORDU.
        let store = InMemoryLastSeenStreakStore(nil)
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3),
            claim: .mock(coins: 20, coinBalance: 999, checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4))
        )
        let model = OdulMerkeziModel(
            checkInService: service,
            wallet: FakeRewardsWallet(100),
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: MockAnalytics(),
            featureFlags: MockFeatureFlags(),
            delegate: RewardsDelegateSpy(),
            lastSeenStreakStore: store
        )
        model.onAppear()
        await model.pendingWork() // A yüklendi: streak 3, loadState .loaded
        #expect(model.coinBalance == 100)

        service.armClaim()
        async let claim: Void = model.claimToday() // claim() gate'te bloklanır
        await service.claimGate.waitForArrival()

        model.resetForAccountSwitch() // hesap değişimi — accountEpoch bump

        await service.claimGate.release() // claim A'nın yanıtıyla (999/streak4) çözülür
        await claim

        // A'nın yanıtı DÜŞÜRÜLDÜ (reset değerleri korunur, cross-account sızıntı yok).
        #expect(model.coinBalance == 0) // 999 DEĞİL
        #expect(model.checkInState == nil) // streak4 DEĞİL
        #expect(store.lastSeenStreak() == nil) // A'nın streak4'ü persist EDİLMEDİ
    }
}

// MARK: - Gate'li check-in servisi (status()'ü deterministik bloklar; claim() serbest geçer)

/// `arm()`'dan sonraki `status()` çağrısını `gate` serbest bırakılana kadar bekleten servis. Uçuştaki
/// tazeleme ↔ claim sıralama yarışını duvar-saati beklemesi OLMADAN deterministik kurar (CI flake yok).
final class GatedCheckInService: CheckInService, @unchecked Sendable {
    let gate = OneShotGate()
    /// claim() çağrısını bloklayan ayrı kapı — claim-uçuştayken-switch yarışı için.
    let claimGate = OneShotGate()
    private let lock = NSLock()
    private var statusResult: CheckInState
    private var claimResult: CheckInClaimResult
    private var armed = false
    private var armedClaim = false
    /// Set edilirse `status()` gate'ten SONRA bu hatayı fırlatır (uçuştaki status()-throw yolu testleri).
    private var statusError: Error?
    /// Set edilirse `claim()` gate'ten SONRA bu hatayı fırlatır (uçuştaki generic-catch fence testleri).
    private var claimError: Error?

    init(status: CheckInState, claim: CheckInClaimResult) {
        statusResult = status
        claimResult = claim
    }

    func arm() {
        lock.withLock { armed = true }
    }

    func armClaim() {
        lock.withLock { armedClaim = true }
    }

    func setStatusError(_ error: Error) {
        lock.withLock { statusError = error }
    }

    func setClaimError(_ error: Error) {
        lock.withLock { claimError = error }
    }

    func status() async throws -> CheckInState {
        let isArmed = lock.withLock { armed }
        if isArmed {
            await gate.wait()
        }
        return try lock.withLock {
            if let statusError {
                throw statusError
            }
            return statusResult
        }
    }

    func claim() async throws -> CheckInClaimResult {
        let isArmed = lock.withLock { armedClaim }
        if isArmed {
            await claimGate.wait()
        }
        return try lock.withLock {
            if let claimError {
                throw claimError
            }
            return claimResult
        }
    }
}

/// İlk `wait()`'i `release()` gelene kadar bekleten tek-atışlık kapı; `waitForArrival()` bekleyen
/// tarafın gate'e ULAŞTIĞINI (bloklandığını) sinyaller.
actor OneShotGate {
    private var released = false
    private var didArrive = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var arrivalWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        didArrive = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        if released {
            return
        }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForArrival() async {
        if didArrive {
            return
        }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
