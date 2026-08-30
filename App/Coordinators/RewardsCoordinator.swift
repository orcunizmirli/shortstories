import AppFoundation
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

    /// Hesap değişimi gözlemcisi — app ömrü boyunca canlı (iptal edilmez): switch hangi sekmede olursa
    /// olsun (Profil'den) yakalanır.
    @ObservationIgnored private var accountObserver: Task<Void, Never>?

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
        startObservingAccountSwitch()
    }

    /// Hesap DEĞİŞİMİNDE (userID farklı bir hesaba geçince) uzun-ömürlü `odulMerkeziModel`'i sıfırlar —
    /// model TabCoordinator ömrü boyunca yaşar, switch'te yeniden yaratılmaz → cross-account state
    /// (checkInState/claimedTaskIDs/coinBalance/lastSeenStreak) sızmasın (05 §3.3, SS-132 sınıfı). link
    /// (guest→AYNI userID korunur, §3.3 sıfır-kayıp) reset TETİKLEMEZ; yalnız farklı-hesaba geçiş (409
    /// switch → userID değişir) tetikler. session-death (userID→nil) ve re-auth (nil→userID) de tetiklemez.
    private func startObservingAccountSwitch() {
        let session = composition.dependencies.session
        accountObserver = Task { [weak self] in
            var lastUserID: String?
            for await state in session.stateUpdates {
                // lastUserID YALNIZ non-nil'de güncellenir → nil-ara-durumdan (loggedOut) geçen switch
                // (u1→loggedOut→u2) yakalanır (self-review2; HomeCoordinator ile simetrik).
                guard let current = state.userID else { continue }
                if let previous = lastUserID, previous != current {
                    self?.odulMerkeziModel.resetForAccountSwitch()
                }
                lastUserID = current
            }
        }
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
