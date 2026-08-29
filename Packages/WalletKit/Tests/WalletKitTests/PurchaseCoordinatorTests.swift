import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// Satın alma orkestrasyonu (SS-090/091): purchase → verify → finish; retry kuyruğu; idempotency;
/// familyShared/revoked/invalidReceipt edge case'leri; transaction updates dinleyicisi.
struct PurchaseCoordinatorTests {
    private struct Harness {
        let coordinator: PurchaseCoordinator
        let store: WalletStore
        let purchases: FakePurchaseService
        let remote: FakeWalletRemote
    }

    private func make(
        purchases: FakePurchaseService = FakePurchaseService(),
        remote: FakeWalletRemote = FakeWalletRemote()
    ) -> Harness {
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        let coordinator = PurchaseCoordinator(
            purchases: purchases,
            remote: remote,
            wallet: store,
            analytics: MockAnalytics(),
            log: MockLogger(),
            appAccountToken: { UUID() }
        )
        return Harness(coordinator: coordinator, store: store, purchases: purchases, remote: remote)
    }

    private func coinsCredited(purchased: Int, version: Int) -> VerifyOutcome {
        .coinsCredited(
            granted: GrantedCoins(coins: purchased, bonusCoins: 0, firstPurchaseBonusApplied: false),
            wallet: .fixture(purchased: purchased, version: version),
            transaction: nil
        )
    }

    // MARK: - Satın alma yolları

    @Test func basariliSatinAlmaKrediEderVeFinishEder() async {
        let sut = make()
        sut.purchases.purchaseResult = .success(.success(.fixture(id: 1001)))
        sut.remote.verifyResults = [.success(coinsCredited(purchased: 1200, version: 5))]

        let result = await sut.coordinator.purchase(productID: "com.shortseries.coins.tier3")

        #expect(result == .completed(transactionID: "1001"))
        #expect(sut.purchases.finished.contains(1001))
        let balance = await sut.store.currentBalance()
        #expect(balance.purchasedCoins == 1200)
    }

    @Test func iptalSessizceDoner() async {
        let sut = make()
        sut.purchases.purchaseResult = .success(.userCancelled)

        let result = await sut.coordinator.purchase(productID: "com.shortseries.coins.tier1")

        #expect(result == .cancelled)
        #expect(sut.purchases.finished.isEmpty)
    }

    @Test func pendingAskToBuyDoner() async {
        let sut = make()
        sut.purchases.purchaseResult = .success(.pending)

        let result = await sut.coordinator.purchase(productID: "com.shortseries.coins.tier1")

        #expect(result == .pending)
        #expect(sut.purchases.finished.isEmpty)
    }

    @Test func abonelikSatinAlmaEntitlementYazar() async {
        let sut = make()
        let transaction = VerifiedTransaction.fixture(
            id: 2002,
            productID: "com.shortseries.vip.weekly",
            kind: .subscription
        )
        sut.purchases.purchaseResult = .success(.success(transaction))
        sut.remote.verifyResults = [.success(.subscriptionUpdated(.vip(plan: .weekly)))]

        let result = await sut.coordinator.purchase(productID: "com.shortseries.vip.weekly")

        #expect(result == .completed(transactionID: "2002"))
        let status = await sut.store.subscriptionStatus()
        #expect(status.isVIP)
        #expect(sut.purchases.finished.contains(2002))
    }

    // MARK: - Kritik kural: backend onayından ÖNCE finish YOK

    @Test func backendHatasindaFinishEdilmezPendingDoner() async {
        let sut = make()
        sut.purchases.purchaseResult = .success(.success(.fixture(id: 1001)))
        sut.remote.verifyResults = [.failure(.network(.server(status: 503)))]

        let result = await sut.coordinator.purchase(productID: "com.shortseries.coins.tier3")

        #expect(result == .verificationPending)
        #expect(sut.purchases.finished.isEmpty) // consumable backend onayından önce finish EDİLMEZ
    }

    @Test func gecersizReceiptTerminalFinishEder() async {
        // TİPLİ 422 RECEIPT_INVALID TERMİNAL'dir: makbuz gerçekten geçersiz, kredi asla gelmez →
        // transaction FINISH edilir (sonsuz per-launch re-verify döngüsü kırılır), kredi YAZILMAZ.
        let sut = make()
        sut.remote.verifyResults = [.success(.invalidReceipt)]

        let outcome = await sut.coordinator.process(.fixture(id: 3003))

        #expect(outcome == .invalidReceipt)
        #expect(sut.purchases.finished.contains(3003)) // terminal → döngü kırıldı
        let balance = await sut.store.currentBalance()
        #expect(balance == .zero) // kredi yazılmadı
    }

    // MARK: - Retry kuyruğu (unfinished)

    @Test func gecersizAgSonrasiRetryUnfinishedKrediEder() async {
        let sut = make()
        let transaction = VerifiedTransaction.fixture(id: 4004)
        sut.purchases.setUnfinished([transaction])
        sut.remote.verifyResults = [
            .failure(.network(.offline)),
            .success(coinsCredited(purchased: 1200, version: 5))
        ]

        await sut.coordinator.retryUnfinished() // 1. deneme başarısız
        #expect(sut.purchases.finished.isEmpty)
        let unfinishedAfterFail = await sut.purchases.unfinishedTransactions()
        #expect(unfinishedAfterFail.count == 1)

        await sut.coordinator.retryUnfinished() // 2. deneme başarılı
        #expect(sut.purchases.finished.contains(4004))
        let balance = await sut.store.currentBalance()
        #expect(balance.purchasedCoins == 1200)
    }

    // MARK: - Idempotency (çift kredi önleme)

    @Test func ayniTransactionIkiKezTekKredi() async {
        // Backend idempotent → aynı snapshot; SET semantiği çift krediyi önler.
        let sut = make()
        let transaction = VerifiedTransaction.fixture(id: 5005)
        sut.remote.verifyResults = [
            .success(coinsCredited(purchased: 1200, version: 5)),
            .success(coinsCredited(purchased: 1200, version: 5))
        ]

        _ = await sut.coordinator.process(transaction)
        _ = await sut.coordinator.process(transaction)

        let balance = await sut.store.currentBalance()
        #expect(balance.purchasedCoins == 1200) // 2400 DEĞİL
    }

    @Test func eszamanliAyniTransactionTekVerifyCagrisi() async {
        // Client-tarafı in-flight dedup: aynı transaction eşzamanlı iki kez → tek verify.
        let sut = make()
        let gate = AsyncGate()
        sut.remote.verifyGate = { await gate.wait() }
        sut.remote.verifyResults = [.success(coinsCredited(purchased: 1200, version: 5))]
        let transaction = VerifiedTransaction.fixture(id: 6006)

        async let first = sut.coordinator.process(transaction)
        while sut.remote.verifyCallCount < 1 {
            await Task.yield()
        }
        let second = await sut.coordinator.process(transaction) // ilk askıdayken
        await gate.open()
        let firstOutcome = await first

        #expect(second == .inFlight)
        #expect(firstOutcome == .credited)
        #expect(sut.remote.verifyCallCount == 1)
    }

    // MARK: - Edge case'ler

    @Test func aileePaylasimliReddedilirVeFinishEdilir() async {
        let sut = make()
        let transaction = VerifiedTransaction.fixture(id: 7007, ownership: .familyShared)

        let outcome = await sut.coordinator.process(transaction)

        #expect(outcome == .rejected)
        #expect(sut.purchases.finished.contains(7007)) // redelivery döngüsünü kes
        #expect(sut.remote.verifyCallCount == 0) // backend'e hiç gitmez
    }

    @Test func iadeRevokeRefreshEderVeFinishEder() async {
        let sut = make()
        let transaction = VerifiedTransaction.fixture(id: 8008, revoked: Date())

        let outcome = await sut.coordinator.process(transaction)

        #expect(outcome == .revoked)
        #expect(sut.purchases.finished.contains(8008))
        #expect(sut.remote.fetchWalletCount >= 1) // yerel state tazelendi
        #expect(sut.remote.verifyCallCount == 0)
    }

    // MARK: - Para-güvenliği: belirsiz HTTP → finish YOK (uçtan uca, GERÇEK WalletRemoteClient)

    /// GERÇEK `WalletRemoteClient` + `MockAPIClient`: HTTP eşlemesinin koordinatör davranışıyla
    /// birleşimini uçtan uca doğrular (Fake outcome enjekte etmez).
    private struct LiveHarness {
        let coordinator: PurchaseCoordinator
        let purchases: FakePurchaseService
        let api: MockAPIClient
    }

    private func makeLive(
        purchases: FakePurchaseService = FakePurchaseService()
    ) -> LiveHarness {
        let api = MockAPIClient()
        let remote = WalletRemoteClient(client: api)
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        let coordinator = PurchaseCoordinator(
            purchases: purchases,
            remote: remote,
            wallet: store,
            analytics: MockAnalytics(),
            log: MockLogger(),
            appAccountToken: { UUID() }
        )
        return LiveHarness(coordinator: coordinator, purchases: purchases, api: api)
    }

    @Test func hamDortYuzDokuzPendingRetryFinishEdilmez() async {
        // PARA KAYBI koruması (uçtan uca): tanınmayan/çıplak 409 başarı SENTEZLENMEZ. Koordinatör
        // pendingRetry döner ve consumable'ı FINISH ETMEZ → StoreKit yeniden teslim eder (retry).
        let sut = makeLive()
        sut.api.stub("/iap/verify", throwing: .network(.server(status: 409)))

        let outcome = await sut.coordinator.process(.fixture(id: 4109))

        #expect(outcome == .pendingRetry)
        #expect(sut.purchases.finished.isEmpty) // kredi yok → finish YOK, transaction unfinished kalır
    }

    @Test func hamDortYuzYirmiIkiPendingRetryFinishEdilmez() async {
        // PARA/DÖNGÜ koruması (uçtan uca): çıplak 422 (RECEIPT_INVALID tipli DEĞİL) terminal sayılmaz →
        // pendingRetry, finish YOK (geçici olabilir; erken finish krediyi kalıcı kaybederdi).
        let sut = makeLive()
        sut.api.stub("/iap/verify", throwing: .network(.server(status: 422)))

        let outcome = await sut.coordinator.process(.fixture(id: 4122))

        #expect(outcome == .pendingRetry)
        #expect(sut.purchases.finished.isEmpty)
    }

    @Test func alreadyProcessedSnapshotYoksaRefreshEder() async {
        let sut = make()
        sut.remote.verifyResults = [.success(.alreadyProcessed(wallet: nil, subscription: nil))]

        let outcome = await sut.coordinator.process(.fixture(id: 9009))

        #expect(outcome == .alreadyProcessed)
        #expect(sut.purchases.finished.contains(9009))
        #expect(sut.remote.fetchWalletCount >= 1)
    }

    // MARK: - Transaction updates dinleyicisi

    @Test func updatesDinleyicisiYayilanTransactioniIsler() async {
        let sut = make()
        sut.remote.verifyResults = [.success(coinsCredited(purchased: 550, version: 3))]

        await sut.coordinator.startObservingTransactions()
        sut.purchases.emit(.fixture(id: 1234))
        sut.purchases.finishUpdates()
        await sut.coordinator.awaitObserver()

        #expect(sut.purchases.finished.contains(1234))
        let balance = await sut.store.currentBalance()
        #expect(balance.purchasedCoins == 550)
    }

    // MARK: - Restore + entitlement tohumu

    @Test func restoreSyncEderVeSnapshotTazeler() async {
        let sut = make()

        try? await sut.coordinator.restore()

        #expect(sut.purchases.syncCount == 1)
        #expect(sut.remote.fetchWalletCount >= 1)
    }

    @Test func storeKitEntitlementTohumuVipVerir() async {
        let sut = make()
        sut.purchases.setEntitlements([
            .fixture(id: 1, productID: "com.shortseries.vip.weekly", kind: .subscription)
        ])

        await sut.coordinator.seedEntitlementsFromStoreKit()

        #expect(await sut.store.hasAccess(to: EpisodeID("any")))
    }
}
