import AppFoundation

/// Playback yetkilendirme servisi (05 §4.4): imzalı HLS URL (+ Faz 2 FairPlay).
/// Her bölüm oynatımından önce çağrılır (istisna: coin unlock 200 yanıtı `playback`
/// bloğunu zaten taşır — o yol WalletKit'tedir, 05 §4.5). Prefetch de aynı ucu kullanır.
public protocol PlaybackServicing: Sendable {
    /// `POST /playback/authorize`. URL yenileme akışı da (SS-022 player tarafı —
    /// proaktif `expiresAt - 60 sn` eşiği ve reaktif CDN 403 kurtarması, 05 §8.1)
    /// AYNI çağrıdır: süresi geçen yetki için yeniden authorize edilir.
    /// Hata eşlemesi AppFoundation `AppError` tipli case'leri üzerinden gelir (05 §10.3):
    /// 403 EPISODE_LOCKED → kilitli-bölüm case'i (details yüküyle; UnlockSheet akışını
    /// çağıran katman tetikler), 410 SIGNED_URL_EXPIRED → `.playback(.signedURLExpired)`.
    /// ContentKit eşleme YAPMAZ; tipli hatayı aynen yüzdürür.
    func authorize(episodeId: EpisodeID) async throws -> PlaybackAuthorization
}

public struct PlaybackAPI: PlaybackServicing {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func authorize(episodeId: EpisodeID) async throws -> PlaybackAuthorization {
        try await client.send(PlaybackAuthorizeEndpoint(episodeId: episodeId)).toDomain()
    }
}
