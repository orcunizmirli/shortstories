import AppFoundation
import ContentKit
import Foundation

/// Disk video cache iskeleti (04 §7.2, SS-043 çekirdek dilimi): ~200 MB LRU.
/// Metadata `AssetCacheIndexing` portu üzerinden kalıcılaşır — kalıcılık katmanı
/// AppFoundation SwiftData'sıdır; **PlayerKit SwiftData import etmez** (04 §2.4).
/// İndirme `AssetDownloading` protokolü arkasındadır; birim testleri sahteyle koşar.
///
/// C2/SS-043 devri: episodeID ↔ yerel konum eşlemesinin kalıcı hydration'ı
/// (`CachedAssetRecordEntity.episodeID` alanı, 05 §2) ve izlenmişlik bilgisinin
/// kalıcılaşması bu iskelette bellek-içidir; tam kapsam SS-043'te tamamlanır.
actor EpisodeCacheStore {
    /// Kanonik disk bütçesi (04 §1 tablosu): ~200 MB LRU.
    static let defaultBudgetBytes: Int64 = 200 * 1024 * 1024
    /// 480p rung seçimi için minimum bitrate anahtar değeri (04 §7.2).
    static let preloadMinimumBitrate: Double = 800_000

    private let cacheIndex: any AssetCacheIndexing
    private let downloader: any AssetDownloading
    private let budgetBytes: Int64
    private let entitlements: any EntitlementChecking
    private let logger: any Logging
    private let now: @Sendable () -> Date

    /// Bellek-içi eşleme (iskelet); kalıcı hydration SS-043'te.
    private var localAssets: [EpisodeID: URL] = [:]
    private var watchedEpisodes: Set<EpisodeID> = []
    private var inFlightDownloads: Set<EpisodeID> = []

    init(
        cacheIndex: any AssetCacheIndexing,
        downloader: any AssetDownloading,
        budgetBytes: Int64 = EpisodeCacheStore.defaultBudgetBytes,
        entitlements: any EntitlementChecking,
        logger: any Logging,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cacheIndex = cacheIndex
        self.downloader = downloader
        self.budgetBytes = budgetBytes
        self.entitlements = entitlements
        self.logger = logger
        self.now = now
    }

    /// Bölümü sessizce ön-indirir (Wi-Fi'da binge hızlandırma, remote config bayraklı).
    /// Politika saf `CachePreloadPolicy`'dedir; kilitli/hücresel/cache'li durumlar atlanır.
    func preload(_ episode: Episode, authorization: PlaybackAuthorization, network: NetworkCondition) async {
        let hasEntitlement = await entitlements.hasAccess(to: episode.id)
        guard CachePreloadPolicy.shouldPreload(
            isPlayableWithoutUnlock: episode.access.isPlayableWithoutUnlock,
            hasEntitlement: hasEntitlement,
            network: network,
            isAlreadyCached: localAssets[episode.id] != nil || inFlightDownloads.contains(episode.id)
        ) else { return }
        guard authorization.isUsable(at: now()) else {
            logger.debug("EpisodeCacheStore: süresi geçmiş yetkiyle preload atlandı episodeID=\(episode.id.rawValue)")
            return
        }

        inFlightDownloads.insert(episode.id)
        defer { inFlightDownloads.remove(episode.id) }
        do {
            let asset = try await downloader.downloadAsset(
                from: authorization.playbackURL,
                minimumBitrate: Self.preloadMinimumBitrate
            )
            localAssets[episode.id] = asset.localURL
            try await cacheIndex.upsert(CachedAssetRecord(
                url: asset.localURL,
                sizeInBytes: asset.sizeInBytes,
                lastAccessAt: now()
            ))
            await evictIfNeeded()
        } catch {
            logger.error("EpisodeCacheStore: preload başarısız episodeID=\(episode.id.rawValue)")
        }
    }

    /// Oynatma kararı girdisi (04 §7.2): yerel asset varsa döner ve LRU defterine
    /// erişim işlenir; kilit kontrolüyle işi yoktur (entitlement her durumda ayrıca).
    func localAsset(for episodeID: EpisodeID) async -> URL? {
        guard let url = localAssets[episodeID] else { return nil }
        try? await cacheIndex.markAccessed(url, at: now())
        return url
    }

    /// Bölüm tamamlandı işareti: izlenmiş bölümler eviction'da önceliklidir (04 §7.2).
    func markWatched(_ episodeID: EpisodeID) {
        watchedEpisodes.insert(episodeID)
    }

    /// Bütçe aşımı denetimi: uygulama açılışında + her indirme sonunda koşar
    /// (04 §7 kabul kriteri: 200 MB 24 saatten uzun aşılamaz).
    func evictIfNeeded(incomingBytes: Int64 = 0) async {
        do {
            let total = try await cacheIndex.totalSizeInBytes()
            let need = CacheEvictionPlanner.bytesToFree(
                totalSizeInBytes: total,
                incomingBytes: incomingBytes,
                budgetBytes: budgetBytes
            )
            guard need > 0 else { return }

            let candidates = try await cacheIndex.evictionCandidates(toFree: need)
            let snapshots = candidates.map { record in
                CacheRecordSnapshot(
                    url: record.url,
                    sizeInBytes: record.sizeInBytes,
                    lastAccessAt: record.lastAccessAt,
                    isWatched: isWatched(localURL: record.url)
                )
            }
            for victim in CacheEvictionPlanner.selectVictims(candidates: snapshots, bytesToFree: need) {
                try await downloader.removeLocalAsset(at: victim.url)
                try await cacheIndex.remove(victim.url)
                if let episodeID = localAssets.first(where: { $0.value == victim.url })?.key {
                    localAssets[episodeID] = nil
                }
            }
        } catch {
            logger.error("EpisodeCacheStore: eviction hatası — bir sonraki koşuda yeniden denenir")
        }
    }

    private func isWatched(localURL: URL) -> Bool {
        guard let episodeID = localAssets.first(where: { $0.value == localURL })?.key else { return false }
        return watchedEpisodes.contains(episodeID)
    }
}
