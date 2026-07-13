import AppFoundation
import Foundation

/// `POST /playback/authorize` wire yanıtı (05 §4.4). Aynı şema unlock yanıtındaki
/// `playback` bloğudur (05 §4.5) — WalletKit unlock akışı bu şemayla hizalanır.
struct PlaybackAuthorizationWire: Decodable, Sendable {
    let episodeId: String
    let playbackURL: URL
    let expiresAt: Date
    let drm: DRMInfoWire?

    func toDomain() -> PlaybackAuthorization {
        PlaybackAuthorization(
            episodeId: EpisodeID(episodeId),
            playbackURL: playbackURL,
            expiresAt: expiresAt,
            drm: drm?.toDomain()
        )
    }
}

struct DRMInfoWire: Decodable, Sendable {
    let scheme: DRMInfo.Scheme
    let licenseURL: URL
    let certificateURL: URL
    let licenseToken: String

    func toDomain() -> DRMInfo {
        DRMInfo(scheme: scheme, licenseURL: licenseURL, certificateURL: certificateURL, licenseToken: licenseToken)
    }
}
