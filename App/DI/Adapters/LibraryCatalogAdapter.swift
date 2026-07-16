import AppFoundation
import ContentKit
import LibraryKit

/// LibraryKit `LibraryCatalogReading` → ContentKit `CatalogServicing` (03 §4 R3/R8). Listem kartları
/// yalnız ID + ilerleme taşır; poster/başlık gibi görüntüleme verisi katalogdan JOIN edilir. Adaptör
/// dizi özetlerini eşzamanlı çeker; bulunamayan/erişilemeyen diziler sözlükten DÜŞER (kontrat:
/// çağıran `isAvailable=false` varsayar). Offline'da katalog çağrısı boş döner → Listem yerelden
/// çalışır (02 §4.12 çevrimdışı-tam-işlevsel), yalnız JOIN metadata'sı eksik kalır.
///
/// F1 sınırı (`episodeNumbers`): `CatalogServicing` bölüm numarasını bölüm-ID'sinden dizi bağlamı
/// olmadan çözemez (`episodes(seriesId:)` dizi-başlıdır). Bu JOIN, katalog cache bölüm indeksine
/// (SS-023 genişlemesi) bağlanana kadar boş döner — bölüm numarası UI'da opsiyoneldir (yüzdeye düşer).
struct CatalogLibraryReading: LibraryCatalogReading {
    private let catalog: any CatalogServicing

    init(catalog: any CatalogServicing) {
        self.catalog = catalog
    }

    func seriesInfo(ids: [SeriesID]) async -> [SeriesID: LibrarySeriesInfo] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        return await withTaskGroup(of: (SeriesID, LibrarySeriesInfo)?.self) { group in
            for id in unique {
                group.addTask { [catalog] in
                    guard let series = try? await catalog.seriesDetail(id: id) else { return nil }
                    return (id, Self.info(from: series))
                }
            }
            var result: [SeriesID: LibrarySeriesInfo] = [:]
            for await entry in group {
                if let entry {
                    result[entry.0] = entry.1
                }
            }
            return result
        }
    }

    func episodeNumbers(ids _: [EpisodeID]) async -> [EpisodeID: Int] {
        // F1: dizi bağlamı olmadan bölüm-ID → numara çözülemez (yukarıdaki nota bakınız).
        [:]
    }

    /// Saf dönüşüm (izole test edilir): ContentKit `Series` → LibraryKit görüntüleme özeti.
    static func info(from series: Series) -> LibrarySeriesInfo {
        LibrarySeriesInfo(
            id: series.id,
            title: series.title,
            coverURL: series.coverURL,
            // Detay başarıyla döndüyse dizi kataloğda mevcuttur; yayından kalkma sunucuda 404'e döner
            // (kayıt sözlükten düşer, çağıran isAvailable=false varsayar).
            isAvailable: true
        )
    }
}
