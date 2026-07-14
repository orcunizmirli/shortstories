import AppFoundation
import Foundation

/// Kalıcı kilit açma kaydı (05 §2.7). Kilitler süresizdir (VIP'ten bağımsız). İçerik
/// referansları `EpisodeID`/`SeriesID` (AppFoundation SharedTypes, R3) ile taşınır.
public struct UnlockRecord: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let episodeID: EpisodeID
    public let seriesID: SeriesID
    public let method: Method
    /// rewardedAd/vip için 0.
    public let coinsSpent: Int
    public let unlockedAt: Date

    public init(
        id: String,
        episodeID: EpisodeID,
        seriesID: SeriesID,
        method: Method,
        coinsSpent: Int,
        unlockedAt: Date
    ) {
        self.id = id
        self.episodeID = episodeID
        self.seriesID = seriesID
        self.method = method
        self.coinsSpent = coinsSpent
        self.unlockedAt = unlockedAt
    }

    public enum Method: String, Sendable, Equatable, CaseIterable, Decodable, UnknownDecodable {
        case coins
        case rewardedAd
        case vip
        case unknown
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case episodeId
        case seriesId
        case method
        case coinsSpent
        case unlockedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        episodeID = try EpisodeID(container.decode(String.self, forKey: .episodeId))
        seriesID = try SeriesID(container.decode(String.self, forKey: .seriesId))
        method = try container.decode(Method.self, forKey: .method)
        coinsSpent = try container.decode(Int.self, forKey: .coinsSpent)
        unlockedAt = try container.decode(Date.self, forKey: .unlockedAt)
    }
}

/// `POST /wallet/unlock` sunucu-kararlı sonucu (05 §4.5). Taşıma katmanı hataları (offline,
/// 5xx) yerine bu enum **iş sonucunu** taşır; ağ hataları `throws AppError` ile yüzer.
public enum UnlockOutcome: Sendable, Equatable {
    /// 200 — kilit açıldı (ya da zaten açıktı; istemci farkı umursamaz, 05 §4.5).
    case unlocked(record: UnlockRecord, wallet: WalletSnapshot, transactions: [CoinTransaction])
    /// 402 INSUFFICIENT_COINS (05 §4.5). `shortfall`/`wallet` yalnız zenginleştirilmiş
    /// eşlemede doludur (bkz. WalletRemoteClient notu).
    case insufficientCoins(shortfall: Int?, wallet: WalletSnapshot?)
    /// 409 PRICE_CHANGED (05 §4.5): sheet fiyatı güncellenir, otomatik harcama yapılmaz.
    case priceChanged(currentPrice: Int?)
}

/// `WalletStore.unlock` çağrısının tipli sonucu — optimistic düşüm + server-otoritatif
/// mutabakat sonrası dönen kullanıcı-görünür sonuç (SS-095).
public enum UnlockResult: Sendable, Equatable {
    case success(UnlockRecord)
    case insufficientCoins(shortfall: Int?)
    case priceChanged(currentPrice: Int?)
    /// Ağ/beklenmeyen hata; optimistic düşüm geri alınmıştır.
    case failed(AppError)
}
