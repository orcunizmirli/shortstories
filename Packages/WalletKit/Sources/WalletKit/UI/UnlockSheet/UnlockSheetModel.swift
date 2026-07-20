import AppFoundation
import Foundation
import Observation

/// UnlockSheet'in tetiklendiği bağlam (06 §6.1). `unlockPrice` feed metadata'sından gelir
/// (05 `unlockPrice`); istemci varsayılan fiyat üretmez — yoksa buton devre dışı (06 §6.6).
public struct UnlockContext: Sendable, Equatable {
    public let seriesID: SeriesID
    public let episodeID: EpisodeID
    public let seriesTitle: String
    public let episodeNumber: Int
    public let unlockPrice: Int?
    public let teaserText: String?
    public let source: UnlockPromptSource
    /// Dizi bazlı otomatik-unlock (binge) tercihi — server'da saklanır (06 §6.4).
    public let autoUnlockEnabled: Bool

    public init(
        seriesID: SeriesID,
        episodeID: EpisodeID,
        seriesTitle: String,
        episodeNumber: Int,
        unlockPrice: Int?,
        teaserText: String? = nil,
        source: UnlockPromptSource,
        autoUnlockEnabled: Bool = false
    ) {
        self.seriesID = seriesID
        self.episodeID = episodeID
        self.seriesTitle = seriesTitle
        self.episodeNumber = episodeNumber
        self.unlockPrice = unlockPrice
        self.teaserText = teaserText
        self.source = source
        self.autoUnlockEnabled = autoUnlockEnabled
    }
}

/// UnlockSheet tetik kaynağı (08 §3.4 `source`).
public enum UnlockPromptSource: String, Sendable, Equatable {
    case autoAdvance = "auto_advance"
    case bolumListesi = "bolum_listesi"
    case diziDetay = "dizi_detay"
}

/// Inline hata sebebi (06 §6.6). View lokalize eder; model semantik taşır (test-edilebilirlik).
public enum UnlockErrorReason: Equatable, Sendable {
    /// "Bağlantı sorunu, tekrar dene" — coin düşülmediği server snapshot ile teyit edilir.
    case network
    /// "Fiyat güncellendi" — server 409, fiyat güncellendi, otomatik harcama yapılmaz.
    case priceChanged
}

/// UnlockSheet intent sözleşmesi — App koordinatörü bağlar (02 §4.6 akışları). Zayıf referans,
/// MainActor (SwiftUI sunum katmanı).
@MainActor
public protocol UnlockSheetDelegate: AnyObject {
    /// Kilit açıldı (coin ya da başka cihazdan VIP) → player devam eder (06 §4.3 kabul kriteri).
    func unlockSheetDidUnlock(episodeID: EpisodeID)
    /// Coin yetersiz / eksi bakiye → CoinMagazasi sheet içi push (06 §6.3).
    func unlockSheetRequestsCoinStore()
    /// VIP upsell'e dokunuldu → VIPAbonelik push (06 §6.2 üçüncül seçenek).
    func unlockSheetRequestsVIP()
    /// Kullanıcı sheet'i kapattı → player kilit ekranında kalır (06 §6.2/6; ödemeye zorlanmaz).
    func unlockSheetDidDismiss()
    /// Otomatik-unlock (binge) tercihi değişti — dizi bazlı, server'a yazılır (06 §6.4).
    func unlockSheet(setAutoUnlock enabled: Bool, seriesID: SeriesID)
}

/// UnlockSheet ekran modeli (SS-093). @Observable/@MainActor; SwiftUI View ince kalır, tüm
/// türetim `UnlockSheetViewState` (saf) + bu modelin durum makinesindedir. Bakiye/entitlement
/// yayınları canlı izlenir (06 §6.5: sheet açıkken bakiye değişirse UI güncellenir).
@MainActor
@Observable
public final class UnlockSheetModel {
    // MARK: - Bağlam (sabit)

    public let seriesTitle: String
    public let episodeNumber: Int
    public let teaserText: String?
    private let seriesID: SeriesID
    private let episodeID: EpisodeID
    private let source: UnlockPromptSource

    // MARK: - Türetilen durum (Observable)

    public private(set) var balance: CoinBalance
    public private(set) var unlockPrice: Int?
    public private(set) var config: UnlockOptionsConfig
    public private(set) var vipIntroEligible: Bool
    /// Otomatik-unlock toggle'ı (06 §6.4). Değişince delegate'e yazılır (View `binding` kullanır).
    public private(set) var autoUnlockEnabled: Bool

    // MARK: - Etkileşim durumu (Observable)

    public private(set) var isUnlocking = false
    public private(set) var errorReason: UnlockErrorReason?
    /// Reklam-ile-aç satırı durumu (SS-114): server-otoriter görünürlük/eylem (`begin()`'de çözülene dek `.hidden`).
    public private(set) var adAvailability: RewardedAdUnlockAvailability = .hidden
    /// Reklam gösterimi/unlock akışı sürüyor (satır loading; çift tetik engellenir).
    public private(set) var isWatchingAd = false
    /// Son reklam denemesinin inline geri bildirimi (fill yok/hata/red); başarı/erken-kapatmada `nil`.
    public private(set) var adWatchError: AdWatchError?

    // MARK: - Bağımlılıklar

    private let wallet: any WalletGateway
    private let analytics: any AnalyticsTracking
    /// Reklam-ile-aç portu (SS-114). Enjekte edilmezse (Faz 1) satır görünmez; App adaptörü bağlar (RewardsKit import yok).
    private let rewardedAdUnlock: (any RewardedAdUnlocking)?
    private let now: @Sendable () -> Date
    private weak var delegate: (any UnlockSheetDelegate)?

    private var balanceTask: Task<Void, Never>?
    private var entitlementTask: Task<Void, Never>?
    private var shownAt: Date?
    private var resolved = false
    private var started = false
    /// Sheet kapandı — `begin()` await'te askıdayken `onDisappear` gelirse gözlem görevlerinin await
    /// SONRASI kurulup asla iptal edilmemesini (kalıcı sızıntı) engeller.
    private var isDisposed = false

    public init(
        context: UnlockContext,
        wallet: any WalletGateway,
        analytics: any AnalyticsTracking,
        delegate: (any UnlockSheetDelegate)?,
        rewardedAdUnlock: (any RewardedAdUnlocking)? = nil,
        config: UnlockOptionsConfig = .phase1,
        vipIntroEligible: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        seriesTitle = context.seriesTitle
        episodeNumber = context.episodeNumber
        teaserText = context.teaserText
        seriesID = context.seriesID
        episodeID = context.episodeID
        source = context.source
        unlockPrice = context.unlockPrice
        autoUnlockEnabled = context.autoUnlockEnabled
        balance = .zero
        self.wallet = wallet
        self.analytics = analytics
        self.delegate = delegate
        self.rewardedAdUnlock = rewardedAdUnlock
        // Reklam satırı başta gizli: `adEnabled` `availability()` çözülene dek false (fill/cap/VIP/A-B bilinmeden yok).
        self.config = UnlockOptionsConfig(coinEnabled: config.coinEnabled, adEnabled: false, vipEnabled: config.vipEnabled)
        self.vipIntroEligible = vipIntroEligible
        self.now = now
    }

    /// Saf görünüm durumu — View doğrudan çizer.
    public var viewState: UnlockSheetViewState {
        UnlockSheetViewState.resolve(
            balance: balance,
            unlockPrice: unlockPrice,
            config: config,
            vipIntroEligible: vipIntroEligible
        )
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        Task { await begin() }
    }

    public func onDisappear() {
        isDisposed = true
        balanceTask?.cancel()
        balanceTask = nil
        entitlementTask?.cancel()
        entitlementTask = nil
    }

    /// Seed bakiye + `episode_unlock_prompt` analitiği + canlı gözlemi başlatır. `onAppear`
    /// tarafından çağrılır; testler doğrudan `await` eder (deterministik seed sırası).
    func begin() async {
        guard !started else { return }
        started = true
        shownAt = now()
        balance = await wallet.currentBalance()
        // Await sırasında sheet kapandıysa gözlem kurma (kalıcı sızıntı olmasın).
        guard !isDisposed else { return }
        // Reklam görünürlüğünü ÖNCE çöz ki `options_shown` doğru alt küme taşısın (port yoksa no-op).
        await refreshAdAvailability()
        guard !isDisposed else { return }
        trackPromptShown()
        startObserving()
    }

    /// Reklam satırı görünürlüğünü port'tan çeker (SS-114): ön-yükler (VIP no-op) + `availability()`; port yoksa no-op.
    private func refreshAdAvailability() async {
        guard let rewardedAdUnlock else { return }
        await rewardedAdUnlock.preload()
        guard !isDisposed else { return }
        await applyAdAvailability(rewardedAdUnlock.availability())
    }

    /// Karar → durum + `config.adEnabled` (`hidden` → satır render edilmez; aksi → görünür etkin/devre dışı).
    private func applyAdAvailability(_ availability: RewardedAdUnlockAvailability) {
        adAvailability = availability
        config = UnlockOptionsConfig(
            coinEnabled: config.coinEnabled,
            adEnabled: availability.isVisible,
            vipEnabled: config.vipEnabled
        )
    }

    /// İki canlı akış (bakiye + entitlement) AYRI görevlerde gözlenir; her akış görev DIŞINDA
    /// yakalanır ve görev `self`'i yalnız ZAYIF tutup her turda güçlüye terfi ettirir → askıda
    /// `for await` self'i tutmaz (retain-cycle yok; onDisappear atlansa bile model dealloc olur ve
    /// sonraki emisyonda döngü kırılır).
    private func startObserving() {
        guard !isDisposed else { return }
        if balanceTask == nil {
            let balances = wallet.balanceUpdates()
            balanceTask = Task { [weak self] in
                for await incoming in balances {
                    guard let self else { break }
                    balance = incoming
                }
            }
        }
        if entitlementTask == nil {
            let entitlements = wallet.entitlementUpdates()
            entitlementTask = Task { [weak self] in
                for await snapshot in entitlements {
                    guard let self else { break }
                    // 06 §6.6: başka cihazdan VIP aktifleşir / bölüm başka yerden açılırsa sheet
                    // kapanır, bölüm oynar. VIP tüm bölümleri açar; ya da bu bölüm açılmış olabilir.
                    if snapshot.isVIP || snapshot.lastUnlockedEpisode == episodeID {
                        completeUnlock()
                    }
                }
            }
        }
    }

    // MARK: - Aksiyonlar

    /// Birincil buton (06 §6.2 #2 / §6.3). Bakiye yeterli → kilidi aç; yetersiz/eksi → mağaza.
    public func primaryAction() async {
        switch viewState.coinState {
        case .sufficient:
            await performUnlock()
        case .insufficient, .balanceProblem:
            delegate?.unlockSheetRequestsCoinStore()
        case .priceUnavailable, nil:
            break // buton zaten devre dışı
        }
    }

    /// VIP upsell satırı (06 §6.2 #5).
    public func vipUpsellTapped() {
        analytics.track(
            "unlock_vip_upsell",
            parameters: [
                "series_id": .string(seriesID.rawValue),
                "episode_id": .string(episodeID.rawValue)
            ]
        )
        delegate?.unlockSheetRequestsVIP()
    }

    /// Reklam-ile-aç satırı (06 §6.2 #4 / §9.3). 30 sn tamamlanınca server SSV kilidi açar → `completeUnlock` (coin
    /// unlock ile AYNI akış → reklam sonrası KESİNTİSİZ oynatma). Erken kapatma/fill-yok/hata/red → ödül YOK.
    public func watchAd() async {
        guard let rewardedAdUnlock, !isWatchingAd, !resolved, adAvailability.isActionable else { return }
        isWatchingAd = true
        adWatchError = nil
        let result = await rewardedAdUnlock.watchAdToUnlock(episodeID: episodeID)
        isWatchingAd = false
        // await sırasında entitlement gözlemi kilidi çözmüş olabilir → sonucu yok say (coin akışıyla simetrik).
        guard !resolved else { return }
        switch result {
        case let .unlocked(remainingToday):
            trackUnlockAd(remainingToday: remainingToday) // kanonik funnel (08 §3.4 unlock_ad); WalletKit sahipli
            completeUnlock()
        case .dismissedEarly:
            break // ödül YOK, hak düşmez, satır olduğu gibi (sessiz — kullanıcı seçimi).
        case .noFill, .failed:
            adWatchError = .temporarilyUnavailable
        case let .capReached(resetsAt):
            applyAdAvailability(.capReached(resetsAt: resetsAt, dailyCap: capDailyCap()))
        case .rewardRejected:
            adWatchError = .rewardRejected
        }
    }

    /// `unlock_ad` (08 §3.4): `ad_unlocks_used_today` = cap − server kalan hak (ikisi de biliniyorsa), `daily_cap` config'ten.
    private func trackUnlockAd(remainingToday: Int?) {
        var parameters: [String: AnalyticsValue] = [
            "series_id": .string(seriesID.rawValue),
            "episode_id": .string(episodeID.rawValue)
        ]
        let cap = capDailyCap()
        if let cap, let remainingToday {
            parameters["ad_unlocks_used_today"] = .int(max(0, cap - remainingToday))
        }
        if let cap {
            parameters["daily_cap"] = .int(cap)
        }
        analytics.track("unlock_ad", parameters: parameters)
    }

    /// capReached'e geçerken "Yarın M yeni hak" için mevcut karardaki `dailyCap`'i korur (429 cap taşımaz).
    private func capDailyCap() -> Int? {
        switch adAvailability {
        case let .available(_, dailyCap): dailyCap
        case let .capReached(_, dailyCap): dailyCap
        case .hidden: nil
        }
    }

    /// Otomatik-unlock toggle (06 §6.4). Dizi bazlı; server'a yazılır.
    public func setAutoUnlock(_ enabled: Bool) {
        guard enabled != autoUnlockEnabled else { return }
        autoUnlockEnabled = enabled
        analytics.track("auto_unlock_toggled", parameters: ["on": .bool(enabled)])
        delegate?.unlockSheet(setAutoUnlock: enabled, seriesID: seriesID)
    }

    /// Kapatma (aşağı çekme / X). Kullanıcı ödemeye zorlanmaz (06 §6.2/6).
    public func dismiss() {
        guard !resolved else { return }
        analytics.track(
            "unlock_sheet_dismissed",
            parameters: ["watched_options_ms": .int(elapsedMillis())]
        )
        delegate?.unlockSheetDidDismiss()
    }

    /// CoinMagazasi'ndan başarılı satın alma sonrası geri dönüş (06 §6.3). Bakiye canlı yayından
    /// zaten güncel; otomatik-unlock AÇIKSA bekleyen bölüm sormadan açılır (binge, §6.4), aksi
    /// halde kullanıcı son dokunuşu kendisi yapar (sürpriz harcama/iade riski).
    public func returnedFromCoinStore() async {
        // Bakiye canlı yayından güncel olmalı; yine de otoritatif değeri okuyup drift'i kapatırız.
        balance = await wallet.currentBalance()
        if autoUnlockEnabled, case .sufficient = viewState.coinState {
            await performUnlock()
        }
    }

    // MARK: - İç

    private func performUnlock() async {
        guard !isUnlocking, !resolved, let price = unlockPrice else { return }
        isUnlocking = true
        errorReason = nil
        let result = await wallet.unlock(episodeID: episodeID, expectedPrice: price)
        isUnlocking = false
        // await sırasında entitlement gözlemi kilidi zaten çözmüş olabilir (başka cihazdan VIP /
        // bölüm başka yerden açıldı → completeUnlock, delegate.unlockSheetDidUnlock). Çözülmüşse
        // sonucu YOK SAY: kapanan/kilidi açılmış sheet üzerine CoinMağazası push'u veya fiyat/hata
        // mutasyonu (çift/tutarsız yönlendirme) yapılmaz.
        guard !resolved else { return }

        switch result {
        case .success:
            completeUnlock()
        case .insufficientCoins:
            // Bakiye server snapshot'ıyla güncellendi; CTA otomatik "insufficient" olur → mağaza.
            delegate?.unlockSheetRequestsCoinStore()
        case let .priceChanged(currentPrice):
            if let currentPrice {
                unlockPrice = currentPrice
            }
            errorReason = .priceChanged
        case let .failed(error):
            errorReason = .network
            analytics.track("unlock_failed", parameters: ["reason": .string(AnalyticsMapping.reason(error))])
        }
    }

    private func completeUnlock() {
        guard !resolved else { return }
        resolved = true
        delegate?.unlockSheetDidUnlock(episodeID: episodeID)
    }

    private func trackPromptShown() {
        var parameters: [String: AnalyticsValue] = [
            "series_id": .string(seriesID.rawValue),
            "episode_id": .string(episodeID.rawValue),
            "coin_balance": .int(balance.totalCoins),
            "options_shown": .string(viewState.optionsShownParameter),
            "source": .string(source.rawValue)
        ]
        if let unlockPrice {
            parameters["unlock_price"] = .int(unlockPrice)
        }
        analytics.track("episode_unlock_prompt", parameters: parameters)
    }

    private func elapsedMillis() -> Int {
        guard let shownAt else { return 0 }
        return max(0, Int(now().timeIntervalSince(shownAt) * 1000))
    }
}
