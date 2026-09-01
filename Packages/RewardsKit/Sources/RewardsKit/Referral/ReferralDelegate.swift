import Foundation

/// `ReferralModel` navigasyon niyetleri — App koordinatörü bağlar (R2: URL kurma/`DeepLinkFactory`
/// ve paylaşım sunumu App'te; RewardsKit `SharePresenter`/`DeepLinkRoute` GÖRMEZ). Zayıf ref, MainActor.
@MainActor
public protocol ReferralDelegate: AnyObject {
    /// Davet paylaş → App paylaşım sayfasını sunar. `url` server'ın verdiği hazır davet linki (varsa);
    /// `nil` ise App `code`'dan kurar. Kod her zaman geçilir (metin fallback'i).
    func referralSharesInvite(code: String, url: URL?)

    /// Redeem SERVER-otoriter bakiyeyi kredilendirdi (OdulMerkezi `rewardsDidCreditBalance` simetriği) → App
    /// `WalletStore`'u tazeler ki Profil/CoinShop gibi cüzdan-tabanlı ekranlar bayat DÜŞÜK bakiye göstermesin
    /// (redeem doğrudan API'ye gider, WalletStore'a yansımaz). Yalnız `.credited`'te çağrılır (conflict/hatada DEĞİL).
    func referralDidCreditBalance()
}
