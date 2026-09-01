import AppFoundation
import Foundation

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
    /// Kilit açıldı → player devam (06 §4.3). `viaVIP`: VIP-türevli (REVOCABLE) mı, bireysel coin/ad (KALICI) mı.
    func unlockSheetDidUnlock(episodeID: EpisodeID, viaVIP: Bool)
    /// Coin yetersiz / eksi bakiye → CoinMagazasi sheet içi push (06 §6.3).
    func unlockSheetRequestsCoinStore()
    /// VIP upsell'e dokunuldu → VIPAbonelik push (06 §6.2 üçüncül seçenek).
    func unlockSheetRequestsVIP()
    /// Kullanıcı sheet'i kapattı → player kilit ekranında kalır (06 §6.2/6; ödemeye zorlanmaz).
    func unlockSheetDidDismiss()
    /// Otomatik-unlock (binge) tercihi değişti — dizi bazlı, server'a yazılır (06 §6.4).
    func unlockSheet(setAutoUnlock enabled: Bool, seriesID: SeriesID)
}
