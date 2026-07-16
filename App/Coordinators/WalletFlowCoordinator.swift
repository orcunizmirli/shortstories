import AppFoundation
import ContentKit
import DiscoverKit
import Foundation
import Observation
import UIKit
import WalletKit

/// Çapraz monetizasyon alt-koordinatörü (03 §3.1): `UnlockSheet → CoinMagazasi → VIPAbonelik`
/// akışı her sekmeden tetiklenebildiği için tek merkezden sunulur (02 §4.6/§5.3). Sheet'ler kök
/// seviyede (`RootTabView`) sunulur — bu koordinatör yalnız sunum durumunu ve WalletKit delegate
/// niyetlerini yönetir. Ekran modelleri kompozisyon kökünden gelir (canlı cüzdan/StoreKit).
@Observable
@MainActor
final class WalletFlowCoordinator {
    private let composition: AppComposition

    /// Non-nil olunca ilgili sheet sunulur. UnlockSheet açıkken Coin/VIP onun ÜZERİNE sunulur
    /// (sheet-içi push davranışı, 02 §4.6); UnlockSheet yoksa doğrudan kökten sunulur.
    private(set) var unlockModel: UnlockSheetModel?
    private(set) var coinShopModel: CoinShopModel?
    private(set) var vipModel: VIPSubscriptionModel?

    /// Kilidi açıldığında (coin/başka-cihaz VIP) Ana Sayfa'ya haber verilir → kilitli kart yerinde
    /// yeniden oynar (04 §9.2). HomeCoordinator bunu bağlar.
    var onEpisodeUnlocked: ((EpisodeID) -> Void)?

    init(composition: AppComposition) {
        self.composition = composition
    }

    // MARK: - Giriş noktaları

    /// Kilitli bölüm bağlamıyla UnlockSheet (DiziDetay intent'i veya deep link'ten). Bekleyen coin/VIP
    /// model'lerini temizler: tek tutarlı sunum yığını (UnlockSheet parent) — çift/hayalet sheet önlenir.
    func presentUnlock(context: UnlockContext) {
        coinShopModel = nil
        vipModel = nil
        unlockModel = composition.makeUnlockSheetModel(context: context, delegate: self)
    }

    /// Kilitli bölüm bağlamını `Episode`+`Series`'ten kurup UnlockSheet sunar (PlayerFeed'den, §4.3.5).
    func presentUnlock(for episode: Episode, in series: Series, source: UnlockPromptSource) {
        let context = UnlockContext(
            seriesID: episode.seriesId,
            episodeID: episode.id,
            seriesTitle: series.title,
            episodeNumber: episode.index,
            unlockPrice: episode.access.unlockPrice,
            teaserText: nil,
            source: source
        )
        presentUnlock(context: context)
    }

    /// LockedEpisodeIntent (DiscoverKit) → UnlockContext (WalletKit) çevirisi + sunum (R2/R3).
    func presentUnlock(intent: LockedEpisodeIntent, source: UnlockPromptSource) {
        let context = UnlockContext(
            seriesID: intent.seriesID,
            episodeID: intent.episodeID,
            seriesTitle: intent.seriesTitle,
            episodeNumber: intent.episodeNumber,
            unlockPrice: intent.unlockPrice,
            teaserText: nil,
            source: source
        )
        presentUnlock(context: context)
    }

    /// CoinMagazasi (Profil/Ödüller bakiye kısayolu, UnlockSheet child'ı veya deep link). VIP ile
    /// aynı anda sunulamaz (tek child/standalone sheet) → bekleyen VIP model'i temizlenir; UnlockSheet
    /// parent olarak KORUNUR (sheet-içi push, 02 §4.6).
    func presentCoinStore(source: CoinShopSource) {
        vipModel = nil
        coinShopModel = composition.makeCoinShopModel(source: source, delegate: self)
    }

    /// VIPAbonelik (Profil VIP satırı, UnlockSheet child'ı veya deep link). Coin ile aynı anda
    /// sunulamaz → bekleyen coin model'i temizlenir; UnlockSheet parent olarak korunur.
    func presentVIP(source: VIPSource) {
        coinShopModel = nil
        vipModel = composition.makeVIPSubscriptionModel(source: source, delegate: self)
    }

    // MARK: - Sunum durumu (RootTabView bunları okur)

    /// Coin sheet UnlockSheet üzerine mi sunulacak (aksi halde kökten standalone).
    var isCoinStoreChildOfUnlock: Bool {
        coinShopModel != nil && unlockModel != nil
    }

    var isVIPChildOfUnlock: Bool {
        vipModel != nil && unlockModel != nil
    }
}

// MARK: - UnlockSheetDelegate (02 §4.6)

extension WalletFlowCoordinator: UnlockSheetDelegate {
    func unlockSheetDidUnlock(episodeID: EpisodeID) {
        // Tüm paywall yığını kapanır, bölüm oynar (06 §4.3).
        coinShopModel = nil
        vipModel = nil
        unlockModel = nil
        onEpisodeUnlocked?(episodeID)
    }

    func unlockSheetRequestsCoinStore() {
        presentCoinStore(source: .unlockSheet)
    }

    func unlockSheetRequestsVIP() {
        presentVIP(source: .unlockSheet)
    }

    func unlockSheetDidDismiss() {
        // `unlockSheetDidUnlock` ile SİMETRİK: UnlockSheet kapanınca üzerindeki child coin/VIP de
        // temizlenir. Aksi halde `unlockModel` nil olunca standalone binding'ler (coin/VIP != nil &&
        // unlock == nil) true'ya döner ve coin/VIP sheet'i kendiliğinden yeniden sunulur (hayalet sheet).
        coinShopModel = nil
        vipModel = nil
        unlockModel = nil
    }

    func unlockSheet(setAutoUnlock enabled: Bool, seriesID: SeriesID) {
        // TODO(F2): dizi-bazlı otomatik-unlock tercihini server'a yaz (06 §6.4). Şimdilik no-op —
        // model kendi durumunu tutar, UI tutarlı kalır.
        _ = (enabled, seriesID)
    }
}

// MARK: - CoinShopDelegate (02 §4.7)

extension WalletFlowCoordinator: CoinShopDelegate {
    func coinShopDidCompletePurchase() {
        if let unlockModel {
            // UnlockSheet'ten gelindi (06 §6.3): mağaza kapanır, kilit kararına OTOMATİK dönülür.
            coinShopModel = nil
            Task { await unlockModel.returnedFromCoinStore() }
        } else {
            // Profil/Ödüller'den gelindi: ekranda kalınır (karar koordinatörün — 02 §4.7).
        }
    }

    func coinShopRequestsDismiss() {
        coinShopModel = nil
    }
}

// MARK: - VIPSubscriptionDelegate (02 §4.8)

extension WalletFlowCoordinator: VIPSubscriptionDelegate {
    func vipSubscriptionDidActivate() {
        // Abonelik aktifleşti: VIP sheet kapanır. UnlockSheet açıksa onun entitlement gözlemcisi
        // `unlockSheetDidUnlock`'ı ayrıca atar (tüm yığını kapatır); burada yalnız VIP'i kapatırız.
        vipModel = nil
    }

    func vipSubscriptionRequestsManagement() {
        // Uygulama içinde ayrı iptal akışı YOK (06 §8.3): iOS abonelik ayarlarına yönlendir.
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    func vipSubscriptionRequestsDismiss() {
        vipModel = nil
    }
}
