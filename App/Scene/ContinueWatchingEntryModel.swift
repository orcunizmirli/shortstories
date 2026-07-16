import AppFoundation
import Foundation
import LibraryKit
import Observation

/// SS-065: Ana Sayfa feed üstündeki "kaldığın yerden devam et" giriş yüzeyinin durum sahibi.
/// Yarım kalan (tamamlanmamış) en güncel bölümü `ContinueWatchingService`'ten (tek kaynak, SS-122)
/// okur; başlığı katalog JOIN portundan (SS-120) getirir. Kayıt yoksa yüzey gizli kalır.
@Observable
@MainActor
final class ContinueWatchingEntryModel {
    /// Görüntülenecek devam kaydı (saf değer). Nil → yüzey çizilmez.
    struct Entry: Equatable, Identifiable {
        let seriesID: SeriesID
        let episodeID: EpisodeID
        let title: String
        let positionSec: Double
        let progressFraction: Double

        var id: EpisodeID {
            episodeID
        }

        var progressPercent: Int {
            Int((progressFraction * 100).rounded())
        }
    }

    private(set) var item: Entry?

    private let service: ContinueWatchingService
    private let catalog: any LibraryCatalogReading
    private var loaded = false

    init(service: ContinueWatchingService, catalog: any LibraryCatalogReading) {
        self.service = service
        self.catalog = catalog
    }

    /// En güncel yarım-kalan bölümü yükler. Ağ senkronunu beklemez (yerel-first, SS-122); sessiz
    /// hata → yüzey gizli. Tekrar çağrılırsa taze okur (favori/izleme değişimi sonrası tazeleme).
    func load() async {
        guard let record = try? await service.continueWatching(limit: 1).first else {
            item = nil
            loaded = true
            return
        }
        let info = await catalog.seriesInfo(ids: [record.seriesID])
        let title = info[record.seriesID]?.title ?? "Kaldığın dizi"
        let fraction = record.durationSec > 0 ? min(1, max(0, record.positionSec / record.durationSec)) : 0
        item = Entry(
            seriesID: record.seriesID,
            episodeID: record.episodeID,
            title: title,
            positionSec: record.positionSec,
            progressFraction: fraction
        )
        loaded = true
    }
}
