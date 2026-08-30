import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import RewardsKit

/// Self-review2 (accountEpoch fence + reset) — kendi kompleks concurrency değişikliklerimde bulunan
/// GERÇEK regresyonların TDD kapanışı. 4 yol:
///  1) refreshCheckIn CATCH dalı generation-fence'siz → başarılı claim SONRASI uçuştaki status() THROW'u
///     loadState'i .failed'e çevirip para-ekranını tam-ekran hataya düşürür (buton regresyonu, throw yolu).
///  2) resetForAccountSwitch uçuştaki load'u iptal/yeniden-tetiklemez → switch load'a denk gelirse B
///     sonsuz .loading spinner'da takılır (startRefreshIfIdle guard'ı yeni yüklemeyi boğar).
///  3) resetForAccountSwitch YERLEŞMİŞ claimFailure'ı temizlemez → A'nın hata banner'ı B ekranında görünür.
///  4) claimToday generic-catch epoch-fence'siz → switch SONRASI uçuştaki claim generic hata verirse
///     A'nın claimFailure'ı B'ye yazılır.
@MainActor
@Suite("OdulMerkezi hesap-değişimi dayanıklılık (self-review2 regresyonları)")
struct OdulMerkeziAccountSwitchRobustnessTests {
    private func makeModel(
        service: GatedCheckInService,
        wallet: any RewardsWalletReading = FakeRewardsWallet(100),
        store: InMemoryLastSeenStreakStore = InMemoryLastSeenStreakStore(nil)
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: service,
            wallet: wallet,
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: MockAnalytics(),
            featureFlags: MockFeatureFlags(),
            delegate: RewardsDelegateSpy(),
            lastSeenStreakStore: store
        )
    }

    /// 1) Başarılı claim SONRASI uçuştaki status() THROW'u loadState'i EZMEMELİ (catch generation-fence).
    @Test func successfulClaimSurvivesInFlightCheckInStatusThrow() async {
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3),
            claim: .mock(coins: 20, coinBalance: 120, checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4))
        )
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork() // A yüklendi: .loaded, todayClaimed false
        #expect(model.loadState == .loaded)

        // Sonraki (warm) status() BLOKLANIR ve serbest kalınca THROW eder.
        service.arm()
        service.setStatusError(URLError(.timedOut))
        model.onAppear() // warm refresh → refreshCheckIn → status() gate'te
        await service.gate.waitForArrival()

        // status BLOKLUYKEN claim BAŞARIR → generation bump, checkInState=claimed, loadState .loaded kalır.
        await model.claimToday()
        #expect(model.checkInState?.todayClaimed == true)
        #expect(model.loadState == .loaded)

        // Bayat status THROW eder → catch generation-guard onu DÜŞÜRMELİ (loadState .failed'e DÜŞMEMELİ).
        await service.gate.release()
        await model.pendingWork()

        #expect(model.loadState == .loaded) // FIX: throw yolu da fence'li → tam-ekran hata YOK
        #expect(model.checkInState?.todayClaimed == true)
    }

    /// 2) Uçuştaki İLK yükleme sırasında hesap değişimi → B sonsuz .loading'de KALMAMALI (yeniden yükler).
    @Test func accountSwitchDuringInFlightLoadReloadsInsteadOfSticking() async {
        let service = GatedCheckInService(
            status: .mock(cycleDay: 1, todayClaimed: false, streakDays: 1),
            claim: .mock(coins: 0, coinBalance: 0, checkin: .mock(cycleDay: 1, todayClaimed: false, streakDays: 1))
        )
        let wallet = FirstCallGatedWallet(500)
        let model = makeModel(service: service, wallet: wallet)

        model.onAppear() // runRefresh → load() → wallet.currentBalance() (1. çağrı) gate'te bloklanır
        await wallet.gate.waitForArrival()

        model.resetForAccountSwitch() // switch (kullanıcı Profil'de): uçuştaki load iptal + loadTask serbest

        // KRİTİK zamanlama: kullanıcı Rewards'a A'nın load'u HÂLÂ UÇUŞTAYKEN döner → onAppear. FIX'siz
        // loadTask non-nil kaldığından startRefreshIfIdle guard'ı reload'u BOĞARDI → sonsuz spinner.
        // FIX ile reset loadTask'ı nil'ler → onAppear taze yükleme başlatır.
        model.onAppear()

        await wallet.gate.release() // A'nın uçuştaki (1.) load'u serbest → epoch-mismatch ile düşer, ezmez

        // FIX: B'nin taze yüklemesi tamamlanır → .loaded (sonsuz spinner DEĞİL).
        var settled = false
        for _ in 0 ..< 2000 where !settled {
            if model.loadState == .loaded {
                settled = true
            } else {
                await Task.yield()
            }
        }
        #expect(model.loadState == .loaded) // sonsuz .loading DEĞİL
        #expect(model.coinBalance == 500) // B'nin bakiyesi yüklendi
    }

    /// 3) YERLEŞMİŞ (settled) claimFailure hesap değişiminde temizlenmeli (A'nın banner'ı B'de görünmesin).
    @Test func accountSwitchClearsSettledClaimFailure() async {
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3),
            claim: .mock(coins: 20, coinBalance: 120, checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4))
        )
        service.setClaimError(URLError(.notConnectedToInternet)) // claim BAŞARISIZ → claimFailure yerleşir
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()

        await model.claimToday() // claim throw → generic catch → claimFailure set (yerleşmiş)
        #expect(model.claimFailure != nil)

        model.resetForAccountSwitch()
        #expect(model.claimFailure == nil) // FIX: A'nın hata banner'ı B'ye sızmaz
    }

    /// 4) Switch SONRASI uçuştaki claim generic hata verirse claimFailure B'ye YAZILMAMALI (catch epoch-fence).
    @Test func inFlightClaimGenericErrorAfterSwitchDoesNotWriteClaimFailure() async {
        let service = GatedCheckInService(
            status: .mock(cycleDay: 3, todayClaimed: false, streakDays: 3),
            claim: .mock(coins: 20, coinBalance: 120, checkin: .mock(cycleDay: 4, todayClaimed: true, streakDays: 4))
        )
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()

        service.armClaim()
        service.setClaimError(URLError(.timedOut)) // claim gate'ten sonra generic hata fırlatır
        async let claim: Void = model.claimToday()
        await service.claimGate.waitForArrival()

        model.resetForAccountSwitch() // switch: epoch bump + claimFailure temizle

        await service.claimGate.release() // A'nın claim'i generic hata ile çözülür
        await claim

        #expect(model.claimFailure == nil) // FIX: uçuştaki A hatası B'nin claimFailure'ını yazmaz
    }
}

// MARK: - İlk çağrısı gate'lenen cüzdan (first-load'ı deterministik askıya alır; sonraki çağrılar geçer)

/// `currentBalance()`'ın YALNIZ ilk çağrısını `gate` serbest bırakılana kadar bekletir; sonraki çağrılar
/// (switch sonrası B'nin yeniden yüklemesi) anında geçer → çift-bekleyen olmadan tek `OneShotGate` yeterli.
final class FirstCallGatedWallet: RewardsWalletReading, @unchecked Sendable {
    let gate = OneShotGate()
    private let lock = NSLock()
    private var balance: Int
    private var firstCallDone = false
    private let multicast = TestMulticast<RewardsBalanceUpdate>()

    init(_ balance: Int) {
        self.balance = balance
        multicast.send(RewardsBalanceUpdate(balance: balance, version: 0))
    }

    func currentBalance() async -> RewardsBalanceUpdate {
        let shouldGate = lock.withLock { () -> Bool in
            let gateIt = !firstCallDone
            firstCallDone = true
            return gateIt
        }
        if shouldGate {
            await gate.wait()
        }
        return lock.withLock { RewardsBalanceUpdate(balance: balance, version: 0) }
    }

    func balanceUpdates() -> AsyncStream<RewardsBalanceUpdate> {
        multicast.subscribe()
    }
}
