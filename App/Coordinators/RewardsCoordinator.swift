import Foundation
import Observation
import RewardsKit

/// Ödüller koordinatörü (03 §3.1): `OdulMerkezi` kökü. F1 (SS-110/111) kapsamında tek cross-feature
/// niyet coin bakiyesi kısayoludur → `CoinMagazasi` (WalletFlow). Görev detayları/rewarded ad
/// (SS-112/113) ileride buraya eklenir.
@Observable
@MainActor
final class RewardsCoordinator {
    private let composition: AppComposition
    private let walletFlow: WalletFlowCoordinator

    /// Kök seviye paylaşım sunumu için zayıf geri-referans (döngü yok; TabCoordinator sahibidir). Davet
    /// paylaşım niyeti buraya akar (RWD-07). `TabCoordinator.init` set eder.
    weak var tabCoordinator: TabCoordinator?

    /// DavetMerkezi push sunum bayrağı (RWD-07) — davet giriş kartı (flag açıkken) bunu tetikler.
    var isPresentingReferral = false

    /// OdulMerkezi modeli — tüm RewardsKit portları kompozisyon kökünde canlı bağlı. `lazy`: delegate
    /// = self (tüm stored prop'lar init olduktan sonra ilk erişimde kurulur).
    @ObservationIgnored private(set) lazy var odulMerkeziModel: OdulMerkeziModel =
        composition.makeOdulMerkeziModel(delegate: self)

    /// DavetMerkezi (referral) modeli — gateway + coin-bakiyesi portu canlı bağlı. `lazy`: delegate = self.
    @ObservationIgnored private(set) lazy var referralModel: ReferralModel =
        composition.makeReferralModel(delegate: self)

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
    }
}

// MARK: - RewardsDelegate (02 §4.9)

extension RewardsCoordinator: RewardsDelegate {
    func rewardsOpensCoinStore() {
        walletFlow.presentCoinStore(source: .odulMerkezi)
    }

    /// Başarılı check-in (streak günü) POZİTİF an'dır → App Store puanlama istemini değerlendir
    /// (RTG-01; 00-genel-bakis.md §294). Kill-switch + terbiye/eşik/sıklık kararı composition/controller'da.
    func rewardsDidClaimCheckIn(streakDay _: Int) {
        composition.requestReviewIfEnabled(.streakDay)
    }

    /// Davet giriş kartı → DavetMerkezi'yi rewards stack'inde iter (RWD-07). Kart yalnız flag açıkken görünür.
    func rewardsOpensReferral() {
        isPresentingReferral = true
    }
}

// MARK: - ReferralDelegate (RWD-07) — davet paylaşımı kök sharePresenter'a akar

extension RewardsCoordinator: ReferralDelegate {
    /// Davet paylaş → kök paylaşım sayfası. Server URL'i varsa onu kullanır; yoksa App `DeepLinkFactory`
    /// koddan kurar (R2: URL kurma App'te). Paylaşım tek kök `sharePresenter`'a akar (diziDetay kalıbı).
    func referralSharesInvite(code: String, url: URL?) {
        tabCoordinator?.sharePresenter.share(url ?? DeepLinkFactory.referralURL(code))
    }
}
