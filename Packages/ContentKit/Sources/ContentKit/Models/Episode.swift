import AppFoundation
import Foundation

/// Bölüm domain modeli (05 §2.2). `id`/`seriesId` AppFoundation SharedTypes ID'leridir.
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: EpisodeID
    public let seriesId: SeriesID
    /// 1 tabanlı bölüm numarası; BolumListesi ızgarası bununla dizilir.
    public let index: Int
    /// Çoğunlukla nil; nil ise istemci "Bölüm \(index)" üretir (lokalizasyon UI'da).
    public let title: String?
    /// Tipik 60–180 sn; progress yüzdesi hesabında payda.
    public let durationSec: Int
    public let thumbnailURL: URL
    /// Kullanıcıya özel erişim durumu — YALNIZ UI ön-gösterimi içindir; oynatma yetkisi
    /// her zaman sunucudan teyit edilir (`POST /playback/authorize`, 05 §2.2 edge case).
    public let access: EpisodeAccess
    /// nil = henüz yayınlanmadı (release schedule, SS-033); nil bölüm oynatılamaz.
    public let publishedAt: Date?

    public init(
        id: EpisodeID,
        seriesId: SeriesID,
        index: Int,
        title: String?,
        durationSec: Int,
        thumbnailURL: URL,
        access: EpisodeAccess,
        publishedAt: Date?
    ) {
        self.id = id
        self.seriesId = seriesId
        self.index = index
        self.title = title
        self.durationSec = durationSec
        self.thumbnailURL = thumbnailURL
        self.access = access
        self.publishedAt = publishedAt
    }

    /// Release schedule kuralı (05 §2.2): `publishedAt == nil` veya gelecekte ise bölüm
    /// henüz yayında değildir (takvimde görünür, oynatılamaz).
    public func isPublished(at date: Date = .now) -> Bool {
        guard let publishedAt else { return false }
        return publishedAt <= date
    }
}

/// Erişim durumu (05 §2.2). VIP kullanıcıya sunucu tüm bölümleri `free`/`unlocked`
/// döner — istemci VIP mantığı UYGULAMAZ.
public struct EpisodeAccess: Codable, Hashable, Sendable {
    public let kind: Kind
    /// Yalnız `.locked` iken anlamlı; dolu ise kanon 50–100 coin, API'den dinamik.
    /// `.locked` + nil = coin yolu kapalı (genişleme noktası, aşağıdaki yardımcılar).
    public let unlockPrice: Int?
    /// UnlockSheet'te "Reklam izle" seçeneğinin görünürlüğü (günlük cap sunucuda).
    public let adUnlockEligible: Bool

    public enum Kind: String, Codable, Sendable, UnknownDecodable {
        case free, locked, unlocked, unknown
    }

    public init(kind: Kind, unlockPrice: Int?, adUnlockEligible: Bool) {
        self.kind = kind
        self.unlockPrice = unlockPrice
        self.adUnlockEligible = adUnlockEligible
    }
}

public extension EpisodeAccess {
    /// Kilitsiz oynatılabilir mi (UI ön-gösterimi). `.unknown` KİLİTLİ varsayılır
    /// (güvenli taraf, 05 §12 kural 4); gerçek durumu authorize çözer.
    var isPlayableWithoutUnlock: Bool {
        switch kind {
        case .free, .unlocked:
            true
        case .locked, .unknown:
            false
        }
    }

    /// Coin ile açma yolu açık mı: yalnız `.locked` + `unlockPrice` dolu (05 §2.2).
    var isCoinUnlockAvailable: Bool {
        kind == .locked && unlockPrice != nil
    }

    /// Genişleme noktası (05 §2.2): `.locked` + `unlockPrice == nil` geçerli bir
    /// kombinasyondur — "bu bölüm coin ile açılamaz" (örn. salt-VIP içerik).
    /// UnlockSheet bu durumda coin satırını çizmez; reklam/VIP seçenekleri
    /// `adUnlockEligible` ve abonelik durumuna göre görünür kalır.
    var isCoinPathClosedLock: Bool {
        kind == .locked && unlockPrice == nil
    }
}
