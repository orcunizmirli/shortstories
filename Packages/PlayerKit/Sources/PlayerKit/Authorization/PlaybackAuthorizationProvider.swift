import AppFoundation
import ContentKit
import Foundation

/// İmzalı URL sağlayıcısı (PlayerKit-internal; 04 §6.4, 05 §8.1):
/// - Taze yetki cache'ten döner; `isUsable` eşiği (expiresAt − 60 sn) geçilmişse
///   yeniden authorize edilir — süresi geçmiş yetkiyle oynatma/prefetch BAŞLATILMAZ.
/// - Aynı bölüm için eşzamanlı istekler TEK uçuşta birleştirilir (coalesced).
/// - 410/403 kurtarması `freshAuthorization` ile cache'i atlayarak taze yetki alır.
actor PlaybackAuthorizationProvider {
    private let service: any PlaybackServicing
    private let now: @Sendable () -> Date
    private let refreshLeeway: Double

    private var cache: [EpisodeID: PlaybackAuthorization] = [:]
    private var inFlight: [EpisodeID: Task<PlaybackAuthorization, Error>] = [:]

    init(
        service: any PlaybackServicing,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshLeeway: Double = 60
    ) {
        self.service = service
        self.now = now
        self.refreshLeeway = refreshLeeway
    }

    /// Kullanılabilir yetki döndürür; gerekirse yeniler. Prefetch ve oynatma aynı
    /// yolu kullanır (05 §4.4).
    func authorization(for episodeID: EpisodeID) async throws -> PlaybackAuthorization {
        if let cached = cache[episodeID], cached.isUsable(at: now(), refreshLeeway: refreshLeeway) {
            return cached
        }
        return try await coalescedFetch(for: episodeID)
    }

    /// Cache'i atlayarak taze yetki alır — oynatma sırasında süre dolduğunda
    /// (410 `signedURLExpired` / CDN 403) kurtarma yolu budur (04 §6.4).
    func freshAuthorization(for episodeID: EpisodeID) async throws -> PlaybackAuthorization {
        invalidate(episodeID)
        return try await coalescedFetch(for: episodeID)
    }

    /// Bölümün cache'lenmiş yetkisini düşürür (ör. entitlement değişimi).
    func invalidate(_ episodeID: EpisodeID) {
        cache[episodeID] = nil
    }

    /// Cache'teki yetki hâlâ kullanılabilir mi — ağ çağrısı YAPMAZ. Warm-hit
    /// tazeliği kontrolünün girdisidir (04 §6.4 kural 4): slot'taki item bayat
    /// yetkiyle hazırlanmışsa çağıran `freshAuthorization` yoluna düşer.
    func hasUsableAuthorization(for episodeID: EpisodeID) -> Bool {
        guard let cached = cache[episodeID] else { return false }
        return cached.isUsable(at: now(), refreshLeeway: refreshLeeway)
    }

    private func coalescedFetch(for episodeID: EpisodeID) async throws -> PlaybackAuthorization {
        if let existing = inFlight[episodeID] {
            return try await existing.value
        }
        let task = Task { [service] in
            try await service.authorize(episodeId: episodeID)
        }
        inFlight[episodeID] = task
        defer { inFlight[episodeID] = nil }
        // Hatalı uçuş cache'lenmez; sonraki istek yeniden dener.
        let auth = try await task.value
        cache[episodeID] = auth
        return auth
    }
}
