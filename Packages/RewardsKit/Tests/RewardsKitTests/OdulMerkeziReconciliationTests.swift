import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import RewardsKit

/// SS-110/111 `OdulMerkeziModel` review davranış düzeltmeleri: coin-kaybı reconciliation (bayat bakiye
/// akışı claim kredisini ezmez, Fix 1), 409 kolunda bakiye tazeleme (Fix 2) ve cold-launch
/// `checkin_streak_break` kalıcılığı (Fix 6, 08 §3.5 win-back KPI). Görev-tarafı reconciliation
/// (Fix 2 görev 409, Fix 3 tazeleme, Fix 4 eventual-consistency) `OdulMerkeziTaskTests`'tedir.
@MainActor
@Suite("SS-110/111 OdulMerkezi reconciliation (review düzeltmeleri)")
struct OdulMerkeziReconciliationTests {
    private func makeModel(
        service: FakeCheckInService = FakeCheckInService(),
        wallet: FakeRewardsWallet = FakeRewardsWallet(100),
        analytics: MockAnalytics = MockAnalytics(),
        lastSeenStreakStore: any LastSeenStreakStoring = InMemoryLastSeenStreakStore()
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: service,
            wallet: wallet,
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: analytics,
            featureFlags: MockFeatureFlags(),
            delegate: RewardsDelegateSpy(),
            lastSeenStreakStore: lastSeenStreakStore
        )
    }

    // MARK: - Fix 1: coinBalance reconciliation (bayat akış değeri claim kredisini EZMEZ)

    @Test func staleBalanceStreamDoesNotOverwriteClaimedBalance() async {
        // Claim yeni bakiye kredilere (320, otoriter). Cüzdan HENÜZ yakalamadan bayat 300'ü tekrar
        // yayınlarsa (replay) bu değer 320'yi EZMEMELİ (coin-kaybı riski, 06 §5.2 "eski değer yeniyi ezmez").
        let claimed = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let wallet = FakeRewardsWallet(300)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .success(.mock(coins: 20, coinBalance: 320, checkin: claimed))
        )
        let model = makeModel(service: service, wallet: wallet)
        model.onAppear()
        await model.pendingWork()

        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        _ = await eventually { model.coinBalance == 300 } // abonelik aktif (300 replay edildi)

        await model.claimToday()
        #expect(model.coinBalance == 320) // otoriter kredi

        wallet.set(300) // BAYAT pre-claim değeri yeniden yayınlandı (cüzdan claim'i henüz işlemedi)
        let dropped = await eventually { model.coinBalance == 300 }
        #expect(dropped == false) // bayat değer düşürüldü, 320 korunur
        #expect(model.coinBalance == 320)
    }

    @Test func balanceStreamResumesAfterClaimCatchUp() async {
        // Guard "sonsuza kadar yok say" DEĞİL: cüzdan claim değerine yakalayınca (320) canlı akış devam
        // eder ve gerçek sonraki değişim (ör. başka ekranda harcama → 280) uygulanır.
        let claimed = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let wallet = FakeRewardsWallet(300)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .success(.mock(coins: 20, coinBalance: 320, checkin: claimed))
        )
        let model = makeModel(service: service, wallet: wallet)
        model.onAppear()
        await model.pendingWork()
        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        _ = await eventually { model.coinBalance == 300 }

        await model.claimToday()
        #expect(model.coinBalance == 320)

        wallet.set(320) // cüzdan yakaladı → guard temizlenir
        _ = await eventually { model.coinBalance == 320 }
        wallet.set(280) // gerçek sonraki değişim → uygulanır
        let applied = await eventually { model.coinBalance == 280 }
        #expect(applied)
    }

    // MARK: - Fix 2: 409 ALREADY_CLAIMED bakiye tazeler (otoriter cüzdandan)

    @Test func alreadyClaimed409ReconcilesBalanceFromWallet() async {
        // 409'da kredi ZATEN düşmüştür (önceki/başka-cihaz claim'i). Başlık bayat kalmasın — 409 kolu
        // cüzdanı yeniden okuyup bakiyeyi reconcile etsin (Fix 2).
        let fresh = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let wallet = FakeRewardsWallet(200)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .failure(CheckInClaimError.alreadyClaimed(fresh))
        )
        let model = makeModel(service: service, wallet: wallet)
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 200)

        wallet.set(230) // kredi cüzdana daha önce düşmüş (otoriter güncel bakiye 230)
        await model.claimToday()
        #expect(model.coinBalance == 230) // 409 kolu başlığı otoriter cüzdandan tazeledi
        #expect(model.checkInState?.todayClaimed == true) // sessiz senkron
        #expect(model.claimFailure == nil) // toast yok
    }

    // MARK: - Fix 6: checkin_streak_break cold-launch'ta kalıcı son-görülen streak'ten

    @Test func streakBreakEmittedOnColdLaunchFromPersistedLastSeen() async {
        // Soğuk açılış: bellek-içi previous nil ama KALICI son-görülen streak 5. Server 0 döndürdü →
        // kırılma "istemci ilk gördüğünde 1 kez" emit edilir (08 §3.5 win-back KPI).
        let store = InMemoryLastSeenStreakStore(5) // önceki oturum 5'te bitti
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 1, todayClaimed: false, streakDays: 0)))
        let analytics = MockAnalytics()
        let model = makeModel(service: service, analytics: analytics, lastSeenStreakStore: store)
        model.onAppear()
        await model.pendingWork()
        let brk = analytics.events.first { $0.name == "checkin_streak_break" }
        #expect(brk?.parameters["broken_at_day"] == .int(5))
        #expect(brk?.parameters["previous_streak_length"] == .int(5))
        #expect(analytics.events.filter { $0.name == "checkin_streak_break" }.count == 1)
        #expect(store.lastSeenStreak() == 0) // güncel server streak'i kalıcı kılındı (sonraki açılış tabanı)
    }

    @Test func noStreakBreakOnFirstEverColdLaunch() async {
        // Hiç kalıcı değer yoksa (ilk açılış) kırılma emit edilmez; server streak'i kalıcı kılınır.
        let store = InMemoryLastSeenStreakStore(nil)
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)))
        let analytics = MockAnalytics()
        let model = makeModel(service: service, analytics: analytics, lastSeenStreakStore: store)
        model.onAppear()
        await model.pendingWork()
        #expect(!analytics.events.contains { $0.name == "checkin_streak_break" })
        #expect(store.lastSeenStreak() == 3)
    }
}
