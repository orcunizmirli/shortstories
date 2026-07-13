import AppFoundation
import Foundation

/// `POST /playback/authorize` yanıtının domain karşılığı (05 §4.4). Aynı şema
/// `POST /wallet/unlock` 200 yanıtındaki `playback` bloğunda da kullanılır (05 §4.5) —
/// Faz 2 FairPlay, API değişikliği olmadan `drm` alanıyla açılır (05 §8.2).
public struct PlaybackAuthorization: Codable, Hashable, Sendable {
    public let episodeId: EpisodeID
    /// İmzalı, süreli HLS master playlist URL'i. Token query'dedir; `AVURLAsset`
    /// ek header gerektirmez. İstemci URL'i olduğu gibi player'a verir.
    public let playbackURL: URL
    /// İstemci imza süresini VARSAYMAZ, bu alanı okur (05 §8.1).
    public let expiresAt: Date
    /// nil = clear HLS (Faz 1); dolu = FairPlay (Faz 2).
    public let drm: DRMInfo?

    public init(episodeId: EpisodeID, playbackURL: URL, expiresAt: Date, drm: DRMInfo?) {
        self.episodeId = episodeId
        self.playbackURL = playbackURL
        self.expiresAt = expiresAt
        self.drm = drm
    }

    /// Yenileme kuralı (05 §8.1): `expiresAt - refreshLeeway` eşiğini geçmiş bir yetkiyle
    /// oynatma/prefetch BAŞLATILMAZ — SS-022 player tarafı önce yeni authorize alır.
    public func isUsable(at date: Date = .now, refreshLeeway: Double = 60) -> Bool {
        date < expiresAt.addingTimeInterval(-refreshLeeway)
    }
}

/// FairPlay DRM bilgisi (05 §4.4 Faz 2 yanıtı). `licenseToken`, license isteğinin
/// `Authorization` header'ında taşınır (05 §8.2); tüketimi PlayerKit'tedir.
public struct DRMInfo: Codable, Hashable, Sendable {
    public let scheme: Scheme
    public let licenseURL: URL
    public let certificateURL: URL
    public let licenseToken: String

    public enum Scheme: String, Codable, Sendable, UnknownDecodable {
        case fairplay, unknown
    }

    public init(scheme: Scheme, licenseURL: URL, certificateURL: URL, licenseToken: String) {
        self.scheme = scheme
        self.licenseURL = licenseURL
        self.certificateURL = certificateURL
        self.licenseToken = licenseToken
    }
}
