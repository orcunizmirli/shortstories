import RewardsKit

// RewardsKit davet-arkadaş (referral) portu + model fabrikası (RWD-07). Ayrı dosya: AppComposition ana
// dosyası 400-satır bütçesinde; referral köprüsü burada gruplanır.

extension AppComposition {
    /// RewardsKit `ReferralGateway` → `APIClient` (/rewards/referral). PREP-BEKLEYEN: canlı endpoint +
    /// ürün/ekonomi kararı hazır olana dek `RewardsFlags.referralCard` KAPALI → `MockReferralGateway`
    /// (deterministik önizleme verisi) bağlanır; flag açılınca canlı adaptör devreye girer.
    var referralGateway: any ReferralGateway {
        if dependencies.featureFlags.value(for: RewardsFlags.referralCard) {
            APIReferralGateway(client: dependencies.apiClient)
        } else {
            MockReferralGateway()
        }
    }

    /// DavetMerkezi (referral) modeli — gateway + coin-bakiyesi portu canlı bağlı.
    func makeReferralModel(delegate: (any ReferralDelegate)?) -> ReferralModel {
        ReferralModel(
            gateway: referralGateway,
            analytics: decoratedAnalytics,
            delegate: delegate
        )
    }
}
