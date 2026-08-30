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

    // MARK: - audit MEDIUM: coinBalance version-monotonic reconciliation (bayat EZMEZ; DONMA yok)

    @Test func staleBalanceStreamDoesNotOverwriteClaimedBalance() async {
        // Claim başlığı 320'ye çeker (otoriter; version bump YOK → baseline 0'da kalır). Cüzdan HENÜZ
        // yakalamadan pre-claim değerini (300, version 0 ≤ baseline) yeniden yayınlarsa version-guard
        // DÜŞÜRÜR → 320 korunur (coin-kaybı riski, 06 §5.2 "eski değer yeniyi ezmez").
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
        _ = await eventually { model.coinBalance == 300 } // ilk load 300 yazdı; abonelik aktif

        await model.claimToday()
        #expect(model.coinBalance == 320) // otoriter kredi

        wallet.set(300, version: 0) // BAYAT pre-claim emisyonu (version ≤ baseline) — cüzdan claim'i işlemedi
        let dropped = await eventually { model.coinBalance == 300 }
        #expect(dropped == false) // version-guard bayat değeri düşürdü, 320 korunur
        #expect(model.coinBalance == 320)
    }

    @Test func newerVersionValuesApplyAfterClaim() async {
        // Guard "sonsuza kadar yok say" DEĞİL: claim SONRASI daha yüksek version'lı emisyonlar uygulanır —
        // cüzdan claim değerine yakalar (320, version 1) sonra gerçek değişim (280, version 2) başlığa geçer.
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

        wallet.set(320) // cüzdan yakaladı (version 1 > baseline 0) → uygulanır (görünür değişim yok)
        wallet.set(280) // gerçek sonraki değişim (version 2) → uygulanır
        let applied = await eventually { model.coinBalance == 280 }
        #expect(applied)
    }

    @Test func legitSpendAppliesAfterClaimDespiteLowerBalance() async {
        // DONMA fix (bu fix'in ÖZÜ): claim başlığı 320'ye çekti (version bump YOK). Kullanıcı başka ekranda
        // harcadı → cüzdan DAHA DÜŞÜK bakiye + DAHA YÜKSEK version yayınlar (200, version 1). Eski `>= awaited`
        // sezgisi `200 >= 320` = false → DÜŞÜRÜR → başlık 320'de KALICI DONARDI. Version-guard: uygular.
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

        wallet.set(200) // MEŞRU harcama: düşük bakiye + yüksek version → DONMADAN uygulanmalı
        #expect(await eventually { model.coinBalance == 200 })
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

    @Test func claimPersistsLastSeenStreakForColdLaunchBaseline() async {
        // Fix 7: claim başarı kolu checkInState'i yazıyordu ama son-görülen streak'i KALICI kılmıyordu →
        // claim SONRASI app-kill → cold-launch, bayat (claim-öncesi, daha düşük) tabana göre yanlış
        // previousStreakLength raporlanırdı (08 §3.5 KPI doğruluğu).
        let store = InMemoryLastSeenStreakStore(nil)
        let claimed = CheckInState.mock(cycleDay: 4, todayClaimed: true, streakDays: 4)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .success(.mock(coins: 20, coinBalance: 120, checkin: claimed))
        )
        let model = makeModel(service: service, lastSeenStreakStore: store)
        model.onAppear()
        await model.pendingWork()
        #expect(store.lastSeenStreak() == 3) // ilk yükleme tabanı

        await model.claimToday()
        #expect(model.streakDays == 4)
        #expect(store.lastSeenStreak() == 4) // claim son-görülen streak'i güncelledi (cold-launch tabanı)
    }

    @Test func resetForAccountSwitchClearsStateAndPreventsCrossAccountBreak() async {
        // Cross-account (SS-132 sınıfı): uzun-ömürlü model hesap değişiminde reset edilmezse önceki hesabın
        // bellek-içi checkInState'i + kalıcı lastSeenStreak'i yeni hesaba taşınıp SAHTE checkin_streak_break
        // atardı. resetForAccountSwitch: state temizlenir + lastSeenStreak.reset() → yeni hesap yüklemesi
        // "ilk gözlem" olur (kırılma yok).
        let store = InMemoryLastSeenStreakStore(nil)
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 5, streakDays: 5)))
        let analytics = MockAnalytics()
        let model = makeModel(service: service, wallet: FakeRewardsWallet(250), analytics: analytics, lastSeenStreakStore: store)
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 250)
        #expect(model.checkInState?.streakDays == 5)
        #expect(store.lastSeenStreak() == 5) // hesap A tabanı persist edildi

        model.resetForAccountSwitch()
        #expect(model.checkInState == nil)
        #expect(model.coinBalance == 0)
        #expect(store.lastSeenStreak() == nil) // A tabanı temizlendi

        // Hesap B: streak 1 (A'nın 5'inden DÜŞÜK). Reset olmasaydı sahte break (5→1) atılırdı.
        service.setStatus(.success(.mock(cycleDay: 1, streakDays: 1)))
        model.onAppear()
        await model.pendingWork()
        #expect(model.checkInState?.streakDays == 1) // hesap B yüklendi
        #expect(!analytics.events.contains { $0.name == "checkin_streak_break" }) // SAHTE break yok
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
