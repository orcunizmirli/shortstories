import AppFoundation
import Testing
@testable import WalletKit

/// UnlockSheet saf görünüm-durumu türetimi (06 §6.2 seçenek sıralaması/görünürlük, §6.3
/// coin-yetersiz, §6.6 fiyat-yok/eksi-bakiye).
struct UnlockSheetViewStateTests {
    private let full = UnlockOptionsConfig.phase1

    @Test func bakiyeYeterliBirincilCoinSufficient() {
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            unlockPrice: 70,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinState == .sufficient(price: 70))
        #expect(state.balanceTotal == 100)
    }

    @Test func bakiyeYetersizShortfallHesaplanir() {
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 35, earnedCoins: 3),
            unlockPrice: 70,
            config: full,
            vipIntroEligible: false
        )
        // 70 − 38 = 32 eksik (06 §6.3 "32 coin daha gerekli").
        #expect(state.coinState == .insufficient(price: 70, shortfall: 32))
    }

    @Test func fiyatYokBirincilDevreDisi() {
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            unlockPrice: nil,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinState == .priceUnavailable)
        // Reklam/VIP çalışır kalır — coin satırı yine görünür (durum: priceUnavailable).
        #expect(state.orderedOptions.contains(.vip))
    }

    @Test func eksiBakiyeBalanceProblemFiyatOnce() {
        // İade sonrası eksi bakiye tüm unlock'ları bloklar; fiyat mevcut olsa bile (06 §6.6).
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: -20, earnedCoins: 0),
            unlockPrice: 70,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinState == .balanceProblem)
    }

    @Test func sabitSiralamaCoinAdVip() {
        let config = UnlockOptionsConfig(coinEnabled: true, adEnabled: true, vipEnabled: true)
        let state = UnlockSheetViewState.resolve(
            balance: .zero, unlockPrice: 70, config: config, vipIntroEligible: false
        )
        #expect(state.orderedOptions == [.coin, .ad, .vip])
        #expect(state.optionsShownParameter == "coin,ad,vip")
    }

    @Test func coinBayragiKapaliSatirYok() {
        // 06 §6.2 görünürlük sözleşmesi: monetization.coin_enabled kapalıysa coin satırı + toggle yok.
        let config = UnlockOptionsConfig(coinEnabled: false, adEnabled: false, vipEnabled: true)
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            unlockPrice: 70,
            config: config,
            vipIntroEligible: true
        )
        #expect(state.coinState == nil)
        #expect(state.orderedOptions == [.vip])
        #expect(state.optionsShownParameter == "vip")
    }

    @Test func vipBayragiKapaliIntroGosterilmez() {
        let config = UnlockOptionsConfig(coinEnabled: true, adEnabled: false, vipEnabled: false)
        let state = UnlockSheetViewState.resolve(
            balance: .zero, unlockPrice: 70, config: config, vipIntroEligible: true
        )
        #expect(!state.showsVIPIntro)
        #expect(state.orderedOptions == [.coin])
    }

    @Test func vipUygunIntroGosterilir() {
        let state = UnlockSheetViewState.resolve(
            balance: .zero, unlockPrice: 70, config: full, vipIntroEligible: true
        )
        #expect(state.showsVIPIntro)
    }

    @Test func faz1VarsayilaniReklamKapali() {
        #expect(UnlockOptionsConfig.phase1.coinEnabled)
        #expect(!UnlockOptionsConfig.phase1.adEnabled)
        #expect(UnlockOptionsConfig.phase1.vipEnabled)
        let state = UnlockSheetViewState.resolve(
            balance: .zero, unlockPrice: 70, config: .phase1, vipIntroEligible: false
        )
        #expect(state.orderedOptions == [.coin, .vip])
    }

    // MARK: - Earned-önce harcama şeffaflığı (SS-115 D2)

    @Test func bakiyeYeterliKarisikEarnedNotuTuretilir() {
        // 60 fiyat; 45 earned + 105 purchased → önce earned düşer (karışık), not dolu.
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 105, earnedCoins: 45),
            unlockPrice: 60,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinSpendNote == .mixed(earned: 45, purchased: 15))
    }

    @Test func bakiyeYetersizEarnedNotuYok() {
        // Insufficient → coin ile açılmayacak, not gösterilmez.
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 10, earnedCoins: 5),
            unlockPrice: 60,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinSpendNote == nil)
    }

    @Test func yalnizPurchasedEarnedNotuYok() {
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            unlockPrice: 60,
            config: full,
            vipIntroEligible: false
        )
        #expect(state.coinSpendNote == nil)
    }

    @Test func coinBayragiKapaliEarnedNotuYok() {
        let config = UnlockOptionsConfig(coinEnabled: false, adEnabled: false, vipEnabled: true)
        let state = UnlockSheetViewState.resolve(
            balance: CoinBalance(purchasedCoins: 105, earnedCoins: 45),
            unlockPrice: 60,
            config: config,
            vipIntroEligible: false
        )
        #expect(state.coinSpendNote == nil)
    }
}
