import AppFoundation
import Foundation
@testable import LibraryKit

// MARK: - Favori senkron backend fake'i

final class FakeFavoritesRemoting: FavoritesRemoting, @unchecked Sendable {
    private let lock = NSLock()
    private var puts: [SeriesID] = []
    private var deletes: [SeriesID] = []
    private var error: AppError?
    private var errorsBySeries: [SeriesID: AppError] = [:]
    /// Reentrancy enjeksiyonu: bir PUT `await` edilirken (askı noktası) tetiklenir. Tek-atışlık —
    /// ilk PUT'ta çalışır ve temizlenir (sonsuz özyinelemeyi önler). Gerçek zamanlama yerine
    /// deterministik askı noktası (05 §3.3 aktör reentrancy senaryosu).
    private var onPut: (@Sendable (SeriesID) async -> Void)?

    init(error: AppError? = nil) {
        self.error = error
    }

    var putCalls: [SeriesID] {
        lock.withLock { puts }
    }

    var deleteCalls: [SeriesID] {
        lock.withLock { deletes }
    }

    func setError(_ error: AppError?) {
        lock.withLock { self.error = error }
    }

    /// Belirli bir diziye özel hata (kalıcı 404 gibi) — kuyruk izolasyonu testleri için.
    func setError(for seriesID: SeriesID, _ error: AppError?) {
        lock.withLock { errorsBySeries[seriesID] = error }
    }

    /// Bir PUT uçarken çalışacak tek-atışlık reentrancy kancası.
    func setOnPut(_ hook: (@Sendable (SeriesID) async -> Void)?) {
        lock.withLock { onPut = hook }
    }

    func putFavorite(_ seriesID: SeriesID) async throws {
        let hook: (@Sendable (SeriesID) async -> Void)? = try lock.withLock {
            if let error = errorsBySeries[seriesID] ?? error {
                throw error
            }
            puts.append(seriesID)
            defer { onPut = nil }
            return onPut
        }
        await hook?(seriesID)
    }

    func deleteFavorite(_ seriesID: SeriesID) async throws {
        try lock.withLock {
            if let error = errorsBySeries[seriesID] ?? error {
                throw error
            }
            deletes.append(seriesID)
        }
    }
}

// MARK: - İzleme ilerlemesi senkron backend fake'i

final class FakeWatchProgressRemoting: WatchProgressRemoting, @unchecked Sendable {
    private let lock = NSLock()
    private var uploaded: [[WatchProgressRecord]] = []
    private var server: [WatchProgressRecord]
    private var uploadError: AppError?
    private var fetchError: AppError?
    /// Bir upload `await` edilirken tetiklenen tek-atışlık reentrancy kancası (deterministik
    /// askı noktası): markSynced watchedAt-körü veri-kaybı yarışını kurar.
    private var onUpload: (@Sendable ([WatchProgressRecord]) async -> Void)?

    init(server: [WatchProgressRecord] = [], uploadError: AppError? = nil, fetchError: AppError? = nil) {
        self.server = server
        self.uploadError = uploadError
        self.fetchError = fetchError
    }

    var uploadedBatches: [[WatchProgressRecord]] {
        lock.withLock { uploaded }
    }

    var uploadedEpisodeIDs: [EpisodeID] {
        lock.withLock { uploaded.flatMap(\.self).map(\.episodeID) }
    }

    func setServer(_ records: [WatchProgressRecord]) {
        lock.withLock { server = records }
    }

    func setUploadError(_ error: AppError?) {
        lock.withLock { uploadError = error }
    }

    /// Bir upload uçarken çalışacak tek-atışlık reentrancy kancası.
    func setOnUpload(_ hook: (@Sendable ([WatchProgressRecord]) async -> Void)?) {
        lock.withLock { onUpload = hook }
    }

    func uploadProgress(_ records: [WatchProgressRecord]) async throws {
        let hook: (@Sendable ([WatchProgressRecord]) async -> Void)? = try lock.withLock {
            if let uploadError {
                throw uploadError
            }
            uploaded.append(records)
            defer { onUpload = nil }
            return onUpload
        }
        await hook?(records)
    }

    func fetchServerProgress() async throws -> [WatchProgressRecord] {
        try lock.withLock {
            if let fetchError {
                throw fetchError
            }
            return server
        }
    }
}

// MARK: - Eşzamanlılık test yardımcıları (deterministik askı/sıralama)

/// `threshold` çağrı gelene dek TÜM çağıranları askıya alan bariyer; eşik dolunca hepsini
/// aynı anda serbest bırakır. Reentrancy/TOCTOU yarışlarını gerçek zamanlama yerine
/// deterministik biçimde kurmak için (iki eşzamanlı toggle'ı aynı bayat okumaya zorlar).
actor TestBarrier {
    private let threshold: Int
    private var arrived = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(threshold: Int) {
        self.threshold = threshold
    }

    func arrive() async {
        arrived += 1
        if arrived >= threshold {
            let pending = waiters
            waiters.removeAll()
            for continuation in pending {
                continuation.resume()
            }
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Gerçek store'u saran, YALNIZ `isFavorite`'a enjekte edilebilir bir askı noktası (bariyer)
/// koyan repository decorator'ı. Eski (kırık) toggle `isFavorite`→`await`→`setFavorite` yolunu
/// izlediğinden bariyer iki toggle'ı bayat okumaya kilitler; yeni atomik `toggleFavorite` yolu
/// bariyere hiç uğramaz (askı noktası yok) — aynı test hem KIRMIZI hem YEŞİL'i ayırt eder.
final class GatedFavoritesRepository: FavoritesRepository, @unchecked Sendable {
    private let base: any FavoritesRepository
    private let isFavoriteBarrier: TestBarrier?

    init(base: any FavoritesRepository, isFavoriteBarrier: TestBarrier? = nil) {
        self.base = base
        self.isFavoriteBarrier = isFavoriteBarrier
    }

    func isFavorite(_ seriesID: SeriesID) async throws -> Bool {
        if let isFavoriteBarrier {
            await isFavoriteBarrier.arrive()
        }
        return try await base.isFavorite(seriesID)
    }

    func favorites() async throws -> [FavoriteRecord] {
        try await base.favorites()
    }

    func addFavorite(_ seriesID: SeriesID, at date: Date) async throws {
        try await base.addFavorite(seriesID, at: date)
    }

    func removeFavorite(_ seriesID: SeriesID) async throws {
        try await base.removeFavorite(seriesID)
    }

    func toggleFavorite(_ seriesID: SeriesID, at date: Date) async throws -> Bool {
        // Atomik yol: bariyere UĞRAMADAN doğrudan store'a delege eder (askı noktası yok).
        try await base.toggleFavorite(seriesID, at: date)
    }

    func pendingSync() async throws -> [PendingFavoriteSync] {
        try await base.pendingSync()
    }

    func confirmAdd(_ seriesID: SeriesID) async throws {
        try await base.confirmAdd(seriesID)
    }

    func confirmRemoval(_ seriesID: SeriesID) async throws {
        try await base.confirmRemoval(seriesID)
    }

    func deleteAll() async throws {
        try await base.deleteAll()
    }
}

// MARK: - Katalog JOIN fake'i

final class FakeLibraryCatalog: LibraryCatalogReading, @unchecked Sendable {
    private let lock = NSLock()
    private var infos: [SeriesID: LibrarySeriesInfo]
    private var numbers: [EpisodeID: Int]

    init(infos: [SeriesID: LibrarySeriesInfo] = [:], numbers: [EpisodeID: Int] = [:]) {
        self.infos = infos
        self.numbers = numbers
    }

    func seriesInfo(ids: [SeriesID]) async -> [SeriesID: LibrarySeriesInfo] {
        lock.withLock { infos.filter { ids.contains($0.key) } }
    }

    func episodeNumbers(ids: [EpisodeID]) async -> [EpisodeID: Int] {
        lock.withLock { numbers.filter { ids.contains($0.key) } }
    }
}

// MARK: - Listem delegate spy'ı

@MainActor
final class ListemDelegateSpy: ListemDelegate {
    struct Resume: Equatable {
        let seriesID: SeriesID
        let episodeID: EpisodeID
        let position: Double
    }

    var played: [SeriesID] = []
    var resumed: [Resume] = []
    var openedDetails: [SeriesID] = []
    var shared: [SeriesID] = []
    var discoverRequested = 0
    var homeRequested = 0

    func listemPlaySeries(seriesID: SeriesID) {
        played.append(seriesID)
    }

    func listemResumeEpisode(seriesID: SeriesID, episodeID: EpisodeID, startPositionSec: Double) {
        resumed.append(Resume(seriesID: seriesID, episodeID: episodeID, position: startPositionSec))
    }

    func listemOpenDetail(seriesID: SeriesID) {
        openedDetails.append(seriesID)
    }

    func listemShare(seriesID: SeriesID) {
        shared.append(seriesID)
    }

    func listemRequestsDiscover() {
        discoverRequested += 1
    }

    func listemRequestsHome() {
        homeRequested += 1
    }
}

// MARK: - Fixture yardımcıları

enum Fixtures {
    static func info(
        _ id: String,
        title: String = "Dizi",
        available: Bool = true
    ) -> LibrarySeriesInfo {
        LibrarySeriesInfo(
            id: SeriesID(id),
            title: title,
            // swiftlint:disable:next force_unwrapping
            coverURL: URL(string: "https://cdn.example/\(id).jpg")!,
            isAvailable: available
        )
    }

    static func progress(
        episode: String,
        series: String = "s-1",
        position: Double = 30,
        duration: Double = 100,
        completed: Bool = false,
        at seconds: TimeInterval
    ) -> WatchProgressRecord {
        WatchProgressRecord(
            episodeID: EpisodeID(episode),
            seriesID: SeriesID(series),
            positionSec: position,
            durationSec: duration,
            completed: completed,
            watchedAt: Date(timeIntervalSince1970: seconds)
        )
    }
}
