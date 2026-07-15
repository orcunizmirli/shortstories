import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import RewardsKit

/// SS-112 `OdulMerkeziModel` görev merkezi entegrasyonu: katalog yükleme (server-otoriter, best-effort),
/// canlı ilerleme overlay'i, SERVER-OTORİTER + idempotent görev claim (optimistik kredi YOK, çift-claim
/// engelleme, 409 sessiz senkron, offline/hata kredi vermez). Analitik registry adları + F2 watchAd flag
/// gate ayrı süitte (`OdulMerkeziMissionAnalyticsTests`).
@MainActor
@Suite("SS-112 OdulMerkezi görev merkezi")
struct OdulMerkeziTaskTests {
    private func makeModel(
        service: FakeCheckInService = FakeCheckInService(),
        wallet: FakeRewardsWallet = FakeRewardsWallet(100),
        taskCatalog: FakeTaskCatalog = FakeTaskCatalog(),
        taskProgress: FakeTaskProgress = FakeTaskProgress(),
        rewardClaiming: FakeRewardClaiming = FakeRewardClaiming(),
        analytics: MockAnalytics = MockAnalytics(),
        flags: MockFeatureFlags = MockFeatureFlags()
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: service,
            wallet: wallet,
            taskCatalog: taskCatalog,
            taskProgress: taskProgress,
            rewardClaiming: rewardClaiming,
            analytics: analytics,
            featureFlags: flags,
            delegate: RewardsDelegateSpy()
        )
    }

    // MARK: - Katalog yükleme

    @Test func loadsTaskCatalogFromServer() async {
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", kind: .watchMinutes, state: .inProgress),
            .mock(id: "b", kind: .favoriteSeries, state: .claimable)
        ]))
        let model = makeModel(taskCatalog: catalog)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems.map(\.id) == ["a", "b"])
        #expect(model.claimableTaskCount == 1)
        #expect(catalog.callCount == 1)
    }

    @Test func loadMergesLiveProgressIntoItems() async {
        let catalog = FakeTaskCatalog(.success([.mock(kind: .watchMinutes, target: 10, progress: 3)]))
        let progress = FakeTaskProgress([.watchMinutes: 7])
        let model = makeModel(taskCatalog: catalog, taskProgress: progress)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems[0].displayedProgress == 7) // server 3 tabanı üstünde canlı 7
        #expect(model.taskItems[0].progressFraction == 0.7)
    }

    @Test func taskCatalogFailureIsBestEffortScreenStillLoads() async {
        // Katalog hatası ekranı DÜŞÜRMEZ — check-in birincildir (görevler ikincil yüzey).
        let catalog = FakeTaskCatalog(.failure(AppError.network(.offline)))
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 2, streakDays: 2)))
        let model = makeModel(service: service, taskCatalog: catalog)
        model.onAppear()
        await model.pendingWork()
        #expect(model.loadState == .loaded)
        #expect(model.taskItems.isEmpty)
    }

    // MARK: - Claim: SERVER-OTORİTER (optimistik DEĞİL)

    @Test func claimCreditsFromServerNotOptimistically() async {
        let claimed = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 20, coinBalance: 320, task: claimed)))
        let model = makeModel(wallet: FakeRewardsWallet(300), taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 300) // claim ÖNCESİ: iyimser kredi yok

        await model.claimTask("a")
        #expect(model.coinBalance == 320) // YALNIZ server yanıtından
        #expect(model.taskItems[0].status == .claimed)
        #expect(model.taskItems[0].isClaimable == false)
        #expect(model.taskClaimCelebration == 1) // haptic + animasyon tetiği
        #expect(model.taskClaimFailure == nil)
        #expect(model.claimableTaskCount == 0)
    }

    // MARK: - Claim guard: claim-edilebilirlik SERVER-otoriter (istemci ilerlemesi DEĞİL)

    @Test func claimBlockedWhenServerStateNotClaimableEvenIfComplete() async {
        // İlerleme hedefe ulaştı ama sunucu henüz claimable yapmadı → claim TETİKLENMEZ (para güvenliği).
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", target: 10, progress: 10, state: .inProgress)]))
        let claiming = FakeRewardClaiming()
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems[0].isComplete)
        #expect(model.taskItems[0].isClaimable == false)

        await model.claimTask("a")
        #expect(claiming.claimCallCount == 0) // istemci eşiği açmaz — sunucu onayı şart
        #expect(model.coinBalance == 100)
    }

    @Test func claimUnknownIDIsNoOp() async {
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", state: .claimable)]))
        let claiming = FakeRewardClaiming()
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        await model.claimTask("does_not_exist")
        #expect(claiming.claimCallCount == 0)
    }

    // MARK: - Idempotent çift-claim engelleme

    @Test func doubleClaimIsIdempotentNoOp() async {
        let claimed = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 20, coinBalance: 220, task: claimed)))
        let model = makeModel(wallet: FakeRewardsWallet(200), taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()

        await model.claimTask("a")
        await model.claimTask("a") // ikinci: görev artık .claimed → guard no-op
        #expect(claiming.claimCallCount == 1)
        #expect(model.coinBalance == 220) // tekrar kredilenmez
        #expect(model.taskClaimCelebration == 1)
    }

    // MARK: - 409 MISSION_NOT_CLAIMABLE: sessiz senkron, kredi yok, toast yok

    @Test func notClaimable409SilentlyResyncsNoCreditNoToast() async {
        let fresh = RewardTask.mock(id: "a", progress: 10, state: .claimed) // sunucu: aslında zaten alınmış
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)]))
        let claiming = FakeRewardClaiming(.failure(RewardClaimError.notClaimable(fresh)))
        let analytics = MockAnalytics()
        let model = makeModel(
            wallet: FakeRewardsWallet(200),
            taskCatalog: catalog,
            rewardClaiming: claiming,
            analytics: analytics
        )
        model.onAppear()
        await model.pendingWork()

        await model.claimTask("a")
        #expect(model.taskItems[0].status == .claimed) // sessiz senkron
        #expect(model.taskClaimFailure == nil) // hata/toast YOK
        #expect(model.coinBalance == 200) // kredilenmez
        #expect(model.taskClaimCelebration == 0)
        #expect(!analytics.events.contains { $0.name == "mission_claim" })
    }

    // MARK: - Fix 2: 409 MISSION_NOT_CLAIMABLE bakiye tazeler (otoriter cüzdandan)

    @Test func notClaimable409ReconcilesBalanceFromWallet() async {
        // 409'da kredi zaten düşmüş olabilir; 409 kolu görevi senkronlarken bakiyeyi de cüzdandan
        // reconcile etsin (Fix 2) — başlık bayat kalmaz.
        let fresh = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)]))
        let claiming = FakeRewardClaiming(.failure(RewardClaimError.notClaimable(fresh)))
        let wallet = FakeRewardsWallet(200)
        let model = makeModel(wallet: wallet, taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 200)

        wallet.set(230) // kredi cüzdana daha önce düşmüş
        await model.claimTask("a")
        #expect(model.coinBalance == 230) // 409 kolu başlığı otoriter cüzdandan tazeledi
        #expect(model.taskItems[0].status == .claimed) // sessiz senkron
        #expect(model.taskClaimFailure == nil)
    }

    // MARK: - Fix 3: tazeleme yaşam döngüsü (07 §4/§4.4)

    @Test func onAppearRefreshesCheckInAndTasksOnEachAppearance() async {
        // Her görünürlükte check-in + görev tazelenir (07 §4.4) — ömür boyu tek-sefer DEĞİL.
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 2, streakDays: 2)))
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", state: .inProgress)]))
        let model = makeModel(service: service, taskCatalog: catalog)
        model.onAppear()
        await model.pendingWork()
        #expect(service.statusCallCount == 1)
        #expect(catalog.callCount == 1)

        model.onAppear() // ikinci görünürlük → yeniden tazele (no-op DEĞİL)
        await model.pendingWork()
        #expect(service.statusCallCount == 2)
        #expect(catalog.callCount == 2)
    }

    @Test func claimTaskSuccessRefetchesCatalog() async {
        // Claim başarısı sonrası KATALOG yeniden çekilir (07 §4.4 refreshTasks).
        let claimed = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)
        ]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 20, coinBalance: 120, task: claimed)))
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        #expect(catalog.callCount == 1)

        await model.claimTask("a")
        #expect(catalog.callCount == 2) // claim sonrası katalog tazelendi
    }

    // MARK: - Fix 4: eventual-consistency guard (yerel .claimed bayat .claimable ile geri dönmez)

    @Test func staleServerClaimableDoesNotRevertLocallyClaimedTask() async {
        // Başarılı claim sonrası görev .claimed. Server eventual-consistency ile HÂLÂ .claimable
        // dönerse (tazeleme) satır .claimed'ten GERİ DÖNMEZ ve mission_complete TEKRAR atılmaz.
        let claimed = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", kind: .watchMinutes, rewardCoins: 20, target: 10, progress: 10, state: .claimable)
        ]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 20, coinBalance: 120, task: claimed)))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming, analytics: analytics)
        model.onAppear()
        await model.pendingWork()

        await model.claimTask("a")
        #expect(model.taskItems.first?.status == .claimed)

        // Server bayat .claimable döndürmeye devam ederken açık bir tazeleme (retry) yap.
        await model.retry()
        #expect(model.taskItems.first?.status == .claimed) // GERİ dönmedi (buton geri gelmez)
        #expect(model.taskItems.first?.isClaimable == false)
        #expect(!analytics.events.contains { $0.name == "mission_complete" }) // tekrar emit yok
        #expect(model.claimableTaskCount == 0)
    }

    // MARK: - Offline / hata: kredi vermez, satır-içi uyarı

    @Test func claimOfflineNoCreditShowsFailureForThatTask() async {
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", state: .claimable)]))
        let claiming = FakeRewardClaiming(.failure(AppError.network(.offline)))
        let model = makeModel(wallet: FakeRewardsWallet(200), taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()

        await model.claimTask("a")
        #expect(model.taskClaimFailure == OdulMerkeziModel.TaskClaimFailure(taskID: "a", reason: .offline))
        #expect(model.coinBalance == 200) // kredilenmez
        #expect(model.taskItems[0].status == .claimable) // durum korunur
        #expect(model.taskClaimCelebration == 0)
        #expect(model.claimingTaskID == nil)
    }

    @Test func claimGenericFailureNoCredit() async {
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", state: .claimable)]))
        let claiming = FakeRewardClaiming(.failure(AppError.unexpected(underlying: "boom")))
        let model = makeModel(wallet: FakeRewardsWallet(200), taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        await model.claimTask("a")
        #expect(model.taskClaimFailure?.reason == .generic)
        #expect(model.coinBalance == 200)
    }

    @Test func successfulClaimClearsPreviousTaskFailure() async {
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", rewardCoins: 15, target: 5, progress: 5, state: .claimable)]))
        let claiming = FakeRewardClaiming(.failure(AppError.network(.offline)))
        let model = makeModel(wallet: FakeRewardsWallet(200), taskCatalog: catalog, rewardClaiming: claiming)
        model.onAppear()
        await model.pendingWork()
        await model.claimTask("a")
        #expect(model.taskClaimFailure?.reason == .offline)

        let claimed = RewardTask.mock(id: "a", progress: 5, state: .claimed)
        claiming.set(.success(.mock(coins: 15, coinBalance: 215, task: claimed)))
        await model.claimTask("a")
        #expect(model.taskClaimFailure == nil)
        #expect(model.coinBalance == 215)
        #expect(model.taskClaimCelebration == 1)
    }

    // MARK: - Canlı ilerleme akışı taskItems'a yansır

    @Test func liveProgressStreamUpdatesItems() async {
        let catalog = FakeTaskCatalog(.success([.mock(kind: .watchMinutes, target: 10, progress: 2)]))
        let progress = FakeTaskProgress([.watchMinutes: 2])
        let model = makeModel(taskCatalog: catalog, taskProgress: progress)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems[0].displayedProgress == 2)

        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        progress.set([.watchMinutes: 9])
        let updated = await eventually { model.taskItems.first?.displayedProgress == 9 }
        #expect(updated)
    }

    // MARK: - Concurrency guard: aynı anda tek claim

    @Test func retryRefetchesCatalog() async {
        let catalog = FakeTaskCatalog(.success([.mock(id: "a", state: .inProgress)]))
        let model = makeModel(taskCatalog: catalog)
        model.onAppear()
        await model.pendingWork()
        #expect(catalog.callCount == 1)
        await model.retry()
        #expect(catalog.callCount == 2)
    }
}
