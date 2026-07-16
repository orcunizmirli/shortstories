import AppFoundation
import ContentKit
import Foundation
import LibraryKit

/// LibraryKit `LibraryCatalogReading` → ContentKit `CatalogServicing` + AppFoundation katalog cache
/// (03 §4 R3/R8, SS-023). Listem kartları yalnız ID + ilerleme taşır; poster/başlık/bölüm-no gibi
/// görüntüleme verisi katalogdan JOIN edilir. JOIN OFFLINE-ÖNCE'dir: dizi özeti/bölüm indeksi önce
/// `CatalogCacheStore`'dan okunur, cache miss'te ağdan çekilip cache'e yazılır — böylece Listem
/// çevrimdışı tam işlevseldir (02 §4.12). Bulunamayan/erişilemeyen diziler sözlükten DÜŞER (kontrat:
/// çağıran `isAvailable=false` varsayar). Ağ çağrıları sınırsız fan-out yerine `maxConcurrency` ile
/// kapaklanır.
///
/// Bölüm numarası (`episodeNumbers`): `CatalogServicing.episodes(seriesId:)` DİZİ-başlıdır, bölüm
/// numarasını salt bölüm-ID'den çözemez. Adaptör önce continue-watching bölüm-ID'lerini dizilerine
/// çözer (`resolveSeries` — watch history tek kaynak), sonra dizi başına bölüm listesini (offline-önce)
/// çekip `episodeID → index` indeksini kurar. Numara UI'da opsiyoneldir (bilinmezse yüzdeye düşer).
///
/// Cache slot sahipliği (F1): ContentKit `CatalogAPI` şu an `CatalogCacheStore`'a DOKUNMAZ, bu yüzden
/// Listem JOIN'i `cachedSeries`/`cachedEpisodeList` slot'larını App-yerel payload şemasıyla (aşağıdaki
/// `Cached*Payload`, `cacheSchemaVersion`) sahiplenir. İleride ContentKit farklı şemayla aynı slot'a
/// yazarsa store'un sürüm-uyumsuzluğu sessiz-silme kuralı (05 §3.2) devreye girer (iki taraf da
/// yeniden çeker) — hiçbir zaman yanlış-decode olmaz.
struct CatalogLibraryReading: LibraryCatalogReading {
    /// App-sahipli Listem JOIN payload şema sürümü (cache slot'ları için).
    static let cacheSchemaVersion = 1
    /// Ağ (seriesDetail / bölüm-listesi) çağrılarında eşzamanlılık kapağı.
    static let maxConcurrency = 4
    /// Dizi bölüm-listesi sayfalamasında güvenlik tavanı (cursor `null`a düşmezse döngü kırılır).
    static let maxEpisodePages = 50

    private let catalog: any CatalogServicing
    private let cache: any CatalogCacheStore
    /// Continue-watching bölüm-ID'sini dizisine çözer (watch history tek kaynak).
    private let resolveSeries: @Sendable ([EpisodeID]) async -> [EpisodeID: SeriesID]
    private let now: @Sendable () -> Date

    init(
        catalog: any CatalogServicing,
        cache: any CatalogCacheStore,
        resolveSeries: @escaping @Sendable ([EpisodeID]) async -> [EpisodeID: SeriesID],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.catalog = catalog
        self.cache = cache
        self.resolveSeries = resolveSeries
        self.now = now
    }

    // MARK: - Dizi özeti JOIN (offline-önce)

    func seriesInfo(ids: [SeriesID]) async -> [SeriesID: LibrarySeriesInfo] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let entries = await Self.mapWithConcurrency(unique, limit: Self.maxConcurrency) { id in
            await loadSeriesInfo(id: id).map { (id, $0) }
        }
        return Dictionary(uniqueKeysWithValues: entries.compactMap(\.self))
    }

    /// Tek dizi: cache-önce oku (hit → ağsız döner); miss'te ağdan çek + cache'e yaz. Ağ da başarısızsa
    /// (offline + cache boş) `nil` — kayıt sözlükten düşer.
    private func loadSeriesInfo(id: SeriesID) async -> LibrarySeriesInfo? {
        let cached = try? await cache.cachedSeries(id: id, expectedSchemaVersion: Self.cacheSchemaVersion)
        if let info = Self.cachedSeriesInfo(from: cached, id: id) {
            return info
        }
        guard let series = try? await catalog.seriesDetail(id: id) else { return nil }
        let info = Self.info(from: series)
        if let payload = try? Self.encodeSeriesInfo(info) {
            try? await cache.storeSeries(
                id: id,
                payload: payload,
                schemaVersion: Self.cacheSchemaVersion,
                etag: nil,
                fetchedAt: now()
            )
            try? await cache.evictCatalogCacheIfNeeded()
        }
        return info
    }

    // MARK: - Bölüm numarası JOIN (dizi bağlamı watch history'den)

    func episodeNumbers(ids: [EpisodeID]) async -> [EpisodeID: Int] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let seriesByEpisode = await resolveSeries(unique)
        guard !seriesByEpisode.isEmpty else { return [:] }

        let uniqueSeries = Array(Set(seriesByEpisode.values))
        let perSeries = await Self.mapWithConcurrency(uniqueSeries, limit: Self.maxConcurrency) { seriesID in
            await (seriesID, episodeIndex(forSeries: seriesID))
        }
        let indexBySeries = Dictionary(uniqueKeysWithValues: perSeries)
        return Self.episodeNumbers(requested: unique, seriesByEpisode: seriesByEpisode, indexBySeries: indexBySeries)
    }

    /// Tek dizinin `episodeID → 1-tabanlı numara` indeksi: cache-önce; miss'te tüm sayfalar ağdan
    /// çekilip indeks kurulur ve cache'e yazılır. Ağ da başarısızsa boş indeks.
    private func episodeIndex(forSeries seriesID: SeriesID) async -> [EpisodeID: Int] {
        let cached = try? await cache.cachedEpisodeList(
            seriesID: seriesID,
            expectedSchemaVersion: Self.cacheSchemaVersion
        )
        if let index = Self.cachedEpisodeIndex(from: cached) {
            return index
        }
        guard let episodes = try? await fetchAllEpisodes(seriesID: seriesID) else { return [:] }
        if let payload = try? Self.encodeEpisodeIndex(episodes) {
            try? await cache.storeEpisodeList(
                seriesID: seriesID,
                payload: payload,
                schemaVersion: Self.cacheSchemaVersion,
                etag: nil,
                fetchedAt: now()
            )
            try? await cache.evictCatalogCacheIfNeeded()
        }
        return Self.episodeIndex(from: episodes)
    }

    /// Dizinin tüm bölümlerini cursor sayfalarını takip ederek çeker (güvenlik tavanlı).
    private func fetchAllEpisodes(seriesID: SeriesID) async throws -> [Episode] {
        var all: [Episode] = []
        var cursor: String?
        var page = 0
        while page < Self.maxEpisodePages {
            let result = try await catalog.episodes(seriesId: seriesID, cursor: cursor)
            all.append(contentsOf: result.items)
            cursor = result.nextCursor
            page += 1
            guard let next = cursor, !next.isEmpty else { break }
        }
        return all
    }

    // MARK: - Saf dönüşümler / kararlar (izole test edilir)

    /// ContentKit `Series` → LibraryKit görüntüleme özeti. Detay başarıyla döndüyse dizi kataloğda
    /// mevcuttur (yayından kalkma sunucuda 404'e döner → kayıt düşer, çağıran isAvailable=false varsayar).
    static func info(from series: Series) -> LibrarySeriesInfo {
        LibrarySeriesInfo(id: series.id, title: series.title, coverURL: series.coverURL, isAvailable: true)
    }

    /// Cache-önce KARAR: cache payload'ı varsa ve decode edilebiliyorsa dizi özetini döner (→ ağ
    /// ATLANIR); yoksa/bozuksa `nil` (→ çağıran ağa gider).
    static func cachedSeriesInfo(from cached: CachedPayload?, id: SeriesID) -> LibrarySeriesInfo? {
        guard let cached, let payload = try? JSONDecoder().decode(CachedSeriesInfoPayload.self, from: cached.payload)
        else { return nil }
        return LibrarySeriesInfo(
            id: id,
            title: payload.title,
            coverURL: payload.coverURL,
            isAvailable: payload.isAvailable
        )
    }

    static func encodeSeriesInfo(_ info: LibrarySeriesInfo) throws -> Data {
        try JSONEncoder().encode(
            CachedSeriesInfoPayload(title: info.title, coverURL: info.coverURL, isAvailable: info.isAvailable)
        )
    }

    /// Bölüm listesinden `episodeID → 1-tabanlı numara` indeksi (SAF). Numara olarak `Episode.index`
    /// kullanılır (05 §2.2: 1-tabanlı bölüm numarası).
    static func episodeIndex(from episodes: [Episode]) -> [EpisodeID: Int] {
        var index: [EpisodeID: Int] = [:]
        index.reserveCapacity(episodes.count)
        for episode in episodes {
            index[episode.id] = episode.index
        }
        return index
    }

    static func encodeEpisodeIndex(_ episodes: [Episode]) throws -> Data {
        let entries = episodes.map { CachedEpisodeEntry(episodeID: $0.id.rawValue, number: $0.index) }
        return try JSONEncoder().encode(CachedEpisodeListPayload(episodes: entries))
    }

    /// Cache-önce KARAR (bölüm listesi): payload varsa ve decode edilebiliyorsa indeksi döner; yoksa `nil`.
    static func cachedEpisodeIndex(from cached: CachedPayload?) -> [EpisodeID: Int]? {
        guard let cached,
              let payload = try? JSONDecoder().decode(CachedEpisodeListPayload.self, from: cached.payload)
        else { return nil }
        var index: [EpisodeID: Int] = [:]
        index.reserveCapacity(payload.episodes.count)
        for entry in payload.episodes {
            index[EpisodeID(entry.episodeID)] = entry.number
        }
        return index
    }

    /// İstenen bölüm-ID'leri için numara seçimi (SAF): her ID → dizisi → dizi indeksindeki numara.
    /// Çözülemeyen/indekste olmayan ID sözlükte YER ALMAZ.
    static func episodeNumbers(
        requested: [EpisodeID],
        seriesByEpisode: [EpisodeID: SeriesID],
        indexBySeries: [SeriesID: [EpisodeID: Int]]
    ) -> [EpisodeID: Int] {
        var result: [EpisodeID: Int] = [:]
        for episodeID in requested {
            if let seriesID = seriesByEpisode[episodeID], let number = indexBySeries[seriesID]?[episodeID] {
                result[episodeID] = number
            }
        }
        return result
    }

    /// Sıralı-korumalı, eşzamanlılık-kapaklı map (sınırsız `withTaskGroup` fan-out'u yerine). En fazla
    /// `limit` görev aynı anda uçar; biri bitince bir sonraki başlar.
    static func mapWithConcurrency<T: Sendable, R: Sendable>(
        _ items: [T],
        limit: Int,
        _ transform: @escaping @Sendable (T) async -> R
    ) async -> [R] {
        guard !items.isEmpty else { return [] }
        let cap = max(1, limit)
        return await withTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: items.count)
            var next = 0
            while next < items.count, next < cap {
                let index = next
                group.addTask { await (index, transform(items[index])) }
                next += 1
            }
            while let (index, value) = await group.next() {
                results[index] = value
                if next < items.count {
                    let index = next
                    group.addTask { await (index, transform(items[index])) }
                    next += 1
                }
            }
            return results.compactMap(\.self)
        }
    }
}

// MARK: - App-sahipli cache payload'ları (opak `Data` — `CatalogCacheStore` slot'ları)

/// Listem dizi-özeti JOIN cache payload'ı (`cachedSeries` slot'u). `id` cache anahtarıdır (payload'da yok).
private struct CachedSeriesInfoPayload: Codable {
    let title: String
    let coverURL: URL
    let isAvailable: Bool
}

/// Listem bölüm-numarası JOIN cache payload'ı (`cachedEpisodeList` slot'u).
private struct CachedEpisodeListPayload: Codable {
    let episodes: [CachedEpisodeEntry]
}

private struct CachedEpisodeEntry: Codable {
    let episodeID: String
    let number: Int
}
