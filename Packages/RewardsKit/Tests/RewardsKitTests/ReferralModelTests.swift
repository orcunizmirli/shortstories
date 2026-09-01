import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import RewardsKit

/// Referral/davet modeli (RWD-07 — client soyutlama): server-otoriter durum yükleme, paylaşım niyeti,
/// SERVER-OTORİTER redeem (başarı yalnız server 200'ünde, transport hatası kredi/başarı vermez, çakışma
/// kullanıcıya-görünür), yeni yüklemede bayat redeem geri bildiriminin temizlenmesi.
@MainActor
@Suite("RWD-07 Referral modeli")
struct ReferralModelTests {
    private func makeModel(
        gateway: FakeReferralGateway = FakeReferralGateway(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: ReferralDelegateSpy = ReferralDelegateSpy()
    ) -> ReferralModel {
        ReferralModel(gateway: gateway, analytics: analytics, delegate: delegate)
    }

    // MARK: - Yükleme

    @Test func loadsStatusFromServer() async {
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics)
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.inviteCode == "DRAMA-7Q2X")
        #expect(model.invitedCount == 5)
        #expect(model.rewardPerReferral == 50)
        #expect(model.canRedeem)
        #expect(analytics.eventNames.contains("referral_view"))
    }

    @Test func statusFailureShowsOfflineScreen() async {
        let gateway = FakeReferralGateway(status: .failure(AppError.network(.offline)))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .offline)
        #expect(model.status == nil)
    }

    @Test func statusGenericFailureShowsFailedScreen() async {
        let gateway = FakeReferralGateway(status: .failure(AppError.network(.server(status: 500))))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .failed)
    }

    // MARK: - Paylaşım

    @Test func shareInviteFiresDelegateWithCodeAndURL() async {
        let analytics = MockAnalytics()
        let delegate = ReferralDelegateSpy()
        let model = makeModel(analytics: analytics, delegate: delegate)
        await model.load()
        model.shareInvite()
        #expect(delegate.lastShare?.code == "DRAMA-7Q2X")
        #expect(delegate.lastShare?.url == URL(string: "https://shortseries.app/r/DRAMA-7Q2X"))
        #expect(analytics.eventNames.contains("referral_shared"))
    }

    @Test func shareInviteBeforeLoadIsNoOp() {
        let delegate = ReferralDelegateSpy()
        let model = makeModel(delegate: delegate)
        model.shareInvite()
        #expect(delegate.lastShare == nil)
    }

    // MARK: - Redeem (server-otoriter)

    @Test func redeemSucceedsOnlyOnServerConfirmation() async {
        let gateway = FakeReferralGateway(redeem: .success(
            .credited(
                reward: ClaimedReward(coins: 50, isStreakBonus: false, expiresAt: nil),
                referral: .mock(canRedeem: false)
            )
        ))
        let analytics = MockAnalytics()
        let model = makeModel(gateway: gateway, analytics: analytics)
        await model.load()
        #expect(model.redeemState == .idle) // redeem ÖNCESİ: optimistik başarı YOK
        await model.redeem("FRIEND-3K9P")
        #expect(model.redeemState == .credited(coins: 50)) // yalnız server onayında
        #expect(model.redeemCelebration == 1)
        #expect(model.canRedeem == false) // taze durum senkronlandı
        #expect(gateway.lastRedeemedCode == "FRIEND-3K9P")
        #expect(analytics.eventNames.contains("referral_redeemed"))
    }

    @Test func redeemCreditedSignalsBalanceRefresh() async {
        // LOW (RewardsKit hunt): redeem .credited server-otoriter bakiyeyi kreditler ama OdulMerkezi kalıbındaki
        // credit-refresh sinyali (delegate) yoktu → Profil/CoinShop başlığı redeem sonrası bayat DÜŞÜK kalırdı.
        let gateway = FakeReferralGateway(redeem: .success(
            .credited(
                reward: ClaimedReward(coins: 50, isStreakBonus: false, expiresAt: nil),
                referral: .mock(canRedeem: false)
            )
        ))
        let delegate = ReferralDelegateSpy()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.load()
        await model.redeem("FRIEND-3K9P")
        #expect(delegate.creditBalanceCalls == 1) // App WalletStore.refresh tetiklenir
    }

    @Test func redeemConflictDoesNotSignalBalanceRefresh() async {
        // Conflict (kredi YOK) credit-refresh sinyali ATMAMALI (yalnız .credited'te).
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.invalidCode)))
        let delegate = ReferralDelegateSpy()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.load()
        await model.redeem("BADCODE")
        #expect(delegate.creditBalanceCalls == 0)
    }

    @Test func redeemTransportErrorGivesNoSuccess() async {
        let gateway = FakeReferralGateway(redeem: .failure(AppError.network(.offline)))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("FRIEND-3K9P")
        #expect(model.redeemFailure == .offline)
        #expect(model.redeemState == .idle) // başarı YOK
        #expect(model.redeemCelebration == 0)
    }

    @Test func redeemInvalidCodeShowsConflict() async {
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.invalidCode)))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("BADCODE")
        #expect(model.redeemState == .conflict(.invalidCode))
        #expect(model.redeemCelebration == 0)
    }

    @Test func redeemSelfReferralConflict() async {
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.selfReferral)))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("DRAMA-7Q2X")
        #expect(model.redeemState == .conflict(.selfReferral))
    }

    @Test func redeemAlreadyRedeemedSyncsStatus() async {
        let fresh = ReferralStatus.mock(canRedeem: false)
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.alreadyRedeemed(fresh))))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("FRIEND-3K9P")
        #expect(model.redeemState == .conflict(.alreadyRedeemed(fresh)))
        #expect(model.status?.canRedeem == false)
        #expect(model.canRedeem == false)
    }

    @Test func redeemAlreadyRedeemedWithoutFreshStatusStillShowsConflict() async {
        // Adaptör taze-durum GET'i başarısız olursa `.alreadyRedeemed(nil)` döner: çakışma yine gösterilir,
        // durum değişmez (bir sonraki yüklemede senkronlanır) — transport hatasına DÜŞMEZ (retry döngüsü yok).
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.alreadyRedeemed(nil))))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("FRIEND-3K9P")
        #expect(model.redeemState == .conflict(.alreadyRedeemed(nil)))
        #expect(model.redeemFailure == nil) // transport hatası DEĞİL
    }

    @Test func blankCodeGuardNoGatewayCall() async {
        let gateway = FakeReferralGateway()
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("   ")
        #expect(gateway.redeemCallCount == 0)
        #expect(model.redeemState == .idle)
    }

    @Test func redeemGuardWhenCannotRedeem() async {
        let gateway = FakeReferralGateway(status: .success(.mock(canRedeem: false)))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("FRIEND-3K9P")
        #expect(gateway.redeemCallCount == 0)
    }

    // MARK: - Bayat geri bildirimin yeni yüklemede temizlenmesi (retained model + re-push)

    @Test func loadClearsStaleRedeemFeedback() async {
        // Model koordinatörde retained; ekran yeniden açıldığında (load) önceki çakışma/hata kalmamalı.
        let gateway = FakeReferralGateway(redeem: .success(.conflict(.invalidCode)))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("BADCODE")
        #expect(model.redeemState == .conflict(.invalidCode))
        await model.load() // ekran yeniden açıldı
        #expect(model.redeemState == .idle)
        #expect(model.redeemFailure == nil)
    }

    // MARK: - Hesap değişimi (cross-account sızıntı — RewardsKit adversarial hunt MEDIUM)

    @Test func resetForAccountSwitchBayatDurumuTemizler() async {
        // Model coordinator ömrü boyu yaşar → hesap değişiminde A'nın davet kodu/sayaçları + redeem-başarı
        // mesajı temizlenmezse B'ye sızar. resetForAccountSwitch bayat durumu temizler.
        let gateway = FakeReferralGateway(redeem: .success(
            .credited(reward: ClaimedReward(coins: 50, isStreakBonus: false, expiresAt: nil), referral: .mock())
        ))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.redeem("FRIEND-CODE")
        #expect(!model.inviteCode.isEmpty) // A'nın kodu yüklü
        #expect(model.redeemState == .credited(coins: 50)) // A'nın başarı mesajı

        model.resetForAccountSwitch()

        #expect(model.loadState == .loading) // spinner (A verisi değil)
        #expect(model.status == nil) // A'nın kodu/sayaçları temizlendi
        #expect(model.inviteCode.isEmpty)
        #expect(model.redeemState == .idle) // A'nın "+50 coin" mesajı temizlendi
        #expect(model.redeemFailure == nil)
    }

    @Test func ucustakiYuklemeResetSonrasiYeniHesabaYazmaz() async {
        // Epoch fence: A'nın load()'u uçuştayken reset olursa (hesap switch), A'nın status'u B'ye YAZILMAMALI
        // (son-yazan-kazanır önlenir).
        let gateway = FakeReferralGateway(status: .success(.mock(inviteCode: "ALICE-CODE")))
        let gate = OneShotGate()
        gateway.statusGate = { await gate.wait() }
        let model = makeModel(gateway: gateway)

        let loadTask = Task { await model.load() } // A load uçuşta (gate'te askıda)
        await gate.waitForArrival()

        model.resetForAccountSwitch() // hesap switch (epoch bump)

        await gate.release() // A'nın status'u çözülür
        await loadTask.value

        #expect(model.status == nil) // A'nın status'u B'ye YAZILMADI
        #expect(model.inviteCode.isEmpty)
        #expect(model.loadState == .loading) // reset sonrası .loading'de kaldı, A .loaded yapmadı
    }
}
