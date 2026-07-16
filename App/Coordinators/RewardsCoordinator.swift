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

    /// OdulMerkezi modeli — tüm RewardsKit portları kompozisyon kökünde canlı bağlı. `lazy`: delegate
    /// = self (tüm stored prop'lar init olduktan sonra ilk erişimde kurulur).
    @ObservationIgnored private(set) lazy var odulMerkeziModel: OdulMerkeziModel =
        composition.makeOdulMerkeziModel(delegate: self)

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
}
