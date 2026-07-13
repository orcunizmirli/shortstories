import AppFoundation
import Foundation

/// Dizi domain modeli (05 §2.1). Property adları istemci sözleşmesidir; wire eşleme
/// yalnız decode sınırında yapılır (`SeriesWire`, 05 kural 7). Bilinçli sapma:
/// `id`, ham `String` yerine AppFoundation SharedTypes `SeriesID`sidir (03 §4 R3).
public struct Series: Codable, Identifiable, Hashable, Sendable {
    public let id: SeriesID
    public let title: String
    public let synopsis: String
    /// Portrait poster (2:3); CDN, imzasız (public görsel).
    public let coverURL: URL
    /// Yatay/hero görsel; Kesfet banner'ları için. Yoksa istemci cover'dan kırpar.
    public let bannerURL: URL?
    public let genres: [Genre]
    public let tags: [Tag]
    /// Toplam planlanan bölüm — DiziDetay "80 Bölüm" rozeti.
    public let episodeCount: Int
    /// Şu an yayında olan bölüm (`<= episodeCount`); BolumListesi bunu baz alır (SS-033).
    public let releasedEpisodeCount: Int
    /// İlk N bölüm ücretsiz (kanon: 5–10 aralığı); istemci bu değeri okur, VARSAYMAZ.
    public let freeEpisodeCount: Int
    public let releaseState: ReleaseState
    /// Ongoing ise bir sonraki bölümün yayın zamanı — "Yeni bölüm: Cuma" etiketi (SS-033).
    public let nextEpisodeAt: Date?
    public let stats: SeriesStats
    public let localeInfo: LocaleInfo
    /// Cache invalidation için (05 §5.3).
    public let updatedAt: Date

    public enum ReleaseState: String, Codable, Sendable, UnknownDecodable {
        case ongoing, completed, unknown
    }

    public init(
        id: SeriesID,
        title: String,
        synopsis: String,
        coverURL: URL,
        bannerURL: URL?,
        genres: [Genre],
        tags: [Tag],
        episodeCount: Int,
        releasedEpisodeCount: Int,
        freeEpisodeCount: Int,
        releaseState: ReleaseState,
        nextEpisodeAt: Date?,
        stats: SeriesStats,
        localeInfo: LocaleInfo,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.synopsis = synopsis
        self.coverURL = coverURL
        self.bannerURL = bannerURL
        self.genres = genres
        self.tags = tags
        self.episodeCount = episodeCount
        self.releasedEpisodeCount = releasedEpisodeCount
        self.freeEpisodeCount = freeEpisodeCount
        self.releaseState = releaseState
        self.nextEpisodeAt = nextEpisodeAt
        self.stats = stats
        self.localeInfo = localeInfo
        self.updatedAt = updatedAt
    }
}

/// Yaklaşık sayılar; UI kısaltır (1.2M) — 05 §2.1.
public struct SeriesStats: Codable, Hashable, Sendable {
    public let viewCount: Int
    public let favoriteCount: Int
    /// Kesfet "Trend" rafı; nil = listede değil.
    public let trendingRank: Int?

    public init(viewCount: Int, favoriteCount: Int, trendingRank: Int?) {
        self.viewCount = viewCount
        self.favoriteCount = favoriteCount
        self.trendingRank = trendingRank
    }
}

public struct LocaleInfo: Codable, Hashable, Sendable {
    /// BCP-47, örn. "en".
    public let audioLanguage: String
    /// Ayarlar'daki altyazı dili seçimiyle kesişim alınır.
    public let subtitleLanguages: [String]

    public init(audioLanguage: String, subtitleLanguages: [String]) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguages = subtitleLanguages
    }
}
