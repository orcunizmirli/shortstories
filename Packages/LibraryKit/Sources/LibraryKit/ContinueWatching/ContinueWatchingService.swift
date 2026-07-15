import AppFoundation
import Foundation

/// İzleme geçmişi + "Devam Et" TEK KAYNAK servisi (SS-122). Ana Sayfa (SS-065), DiziDetay
/// (SS-081), Listem (SS-120) ve push (F2) "kaldığı yer" verisini yalnız buradan alır — çift
/// kaynak/çelişki olmaz. Optimistik yerel yazma (`WatchHistoryRepository`, SwiftData) + sunucu
/// senkron. `import SwiftData` YOK.
///
/// Actor: `synchronize()` tek-uçuşlu (push/pull örtüşmez).
public actor ContinueWatchingService {
    private let repository: any WatchHistoryRepository
    private let remoting: any WatchProgressRemoting
    private var isSyncing = false

    public init(repository: any WatchHistoryRepository, remoting: any WatchProgressRemoting) {
        self.repository = repository
        self.remoting = remoting
    }

    // MARK: - Yazma (optimistik; `pendingUpload` olarak birikir)

    /// "Kaldığı yer"i kaydeder (upsert, last-write-wins). SS-123 raporlaması bu kaydı besler.
    public func recordProgress(_ record: WatchProgressRecord) async throws {
        try await repository.saveProgress(record)
    }

    /// Alan-alan kayıt (player/feed çağrı ergonomisi). `completed` çağıran tarafından ≥ %90
    /// kuralıyla belirlenir (05 §2.11).
    public func recordProgress(
        episodeID: EpisodeID,
        seriesID: SeriesID,
        positionSec: Double,
        durationSec: Double,
        completed: Bool,
        at date: Date = Date()
    ) async throws {
        try await recordProgress(
            WatchProgressRecord(
                episodeID: episodeID,
                seriesID: seriesID,
                positionSec: positionSec,
                durationSec: durationSec,
                completed: completed,
                watchedAt: date
            )
        )
    }

    // MARK: - Okuma (tek kaynak)

    public func progress(forEpisode episodeID: EpisodeID) async throws -> WatchProgressRecord? {
        try await repository.progress(forEpisode: episodeID)
    }

    public func progress(forSeries seriesID: SeriesID) async throws -> [WatchProgressRecord] {
        try await repository.progress(forSeries: seriesID)
    }

    /// Bir dizinin EN GÜNCEL ilerlemesi (DiziDetay "İzlemeye Başla / Devam Et" CTA'sının kaynağı,
    /// SS-081). Hiç izlenmediyse nil. Store'un hedefli tek-kayıt sorgusunu kullanır — tüm dizi
    /// kayıtlarını çekip bellekte `.max` etmez (bulgu #11).
    public func latestProgress(forSeries seriesID: SeriesID) async throws -> WatchProgressRecord? {
        try await repository.latestProgress(forSeries: seriesID)
    }

    /// "Devam Et" listesi (tamamlanmamış, `watchedAt` azalan). `limit <= 0` tümü.
    public func continueWatching(limit: Int = 0) async throws -> [WatchProgressRecord] {
        try await repository.continueWatching(limit: limit)
    }

    // MARK: - Sunucu senkron (push bekleyenler + pull birleştir)

    public func pendingUploadCount() async throws -> Int {
        try await repository.pendingUploads().count
    }

    /// İki yönlü senkron: (1) bekleyen yerel kayıtları batch yükle + `markSynced`; (2) sunucu
    /// geçmişini çekip birleştir (`mergeServerProgress` — yerel yeni pending korunur). Tek-uçuşlu.
    /// Çevrimdışıysa sessizce ertelenir; diğer hatalar yüzeye çıkar.
    public func synchronize() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let pending = try await repository.pendingUploads()
            if !pending.isEmpty {
                try await remoting.uploadProgress(pending)
                try await repository.markSynced(uploaded: pending)
            }
            let server = try await remoting.fetchServerProgress()
            try await repository.mergeServerProgress(server)
        } catch let error as AppError where error == .network(.offline) {
            // Bekleyenler `pendingUpload` kalır; bağlantı dönünce yeniden denenir (SS-123).
        }
    }
}
