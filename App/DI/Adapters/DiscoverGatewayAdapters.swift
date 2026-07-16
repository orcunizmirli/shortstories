import AppFoundation
import ContentKit
import DiscoverKit
import LibraryKit

// DiscoverKit gateway'lerinin canlı adaptörleri (R2/R8). DiziDetay izleme geçmişi + favori köprüleri
// LibraryKit'in TEK KAYNAK servislerine bağlanır; DiscoverKit LibraryKit'i import ETMEZ, App bağlar.

/// DiscoverKit `WatchHistoryReading` → LibraryKit `ContinueWatchingService` (SS-080 CTA). Dizinin en
/// güncel ilerlemesini verir; `WatchProgressRecord` → ContentKit `WatchProgress`'e map eder. Hata
/// (nadir yerel okuma) `nil`'e düşürülür (CTA "İzlemeye Başla"ya döner — güvenli varsayılan).
struct ContinueWatchingHistoryReading: DiscoverKit.WatchHistoryReading {
    private let service: ContinueWatchingService

    init(service: ContinueWatchingService) {
        self.service = service
    }

    func latestProgress(forSeries seriesID: SeriesID) async -> WatchProgress? {
        guard let record = try? await service.latestProgress(forSeries: seriesID) else { return nil }
        return Self.watchProgress(from: record)
    }

    /// Saf dönüşüm (izole test edilir): AppFoundation kayıt tipi → ContentKit domain tipi.
    static func watchProgress(from record: WatchProgressRecord) -> WatchProgress {
        WatchProgress(
            episodeId: record.episodeID,
            seriesId: record.seriesID,
            positionSec: record.positionSec,
            durationSec: record.durationSec,
            completed: record.completed,
            watchedAt: record.watchedAt
        )
    }
}

/// DiscoverKit `FavoritesGateway` → LibraryKit `FavoritesService` (SS-081 optimistik toggle). `isFavorite`
/// hataları `false`'a düşürülür (görünmez favori güvenli varsayılan); `setFavorite` hatayı yüzdürür
/// (model optimistik değişimi geri alır).
struct FavoritesServiceGateway: DiscoverKit.FavoritesGateway {
    private let service: FavoritesService

    init(service: FavoritesService) {
        self.service = service
    }

    func isFavorite(_ seriesID: SeriesID) async -> Bool {
        await (try? service.isFavorite(seriesID)) ?? false
    }

    func setFavorite(_ isFavorite: Bool, seriesID: SeriesID) async throws {
        try await service.setFavorite(isFavorite, seriesID: seriesID)
    }
}
