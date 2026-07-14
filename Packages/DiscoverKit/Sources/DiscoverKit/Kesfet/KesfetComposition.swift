import ContentKit
import Foundation

/// Kesfet ekranının saf, türetilmiş görünüm kompozisyonu (02 §4.10). Girdi: `DiscoverContent`
/// (banner + koleksiyon rafları) + seçili tür filtresi + "şimdi" zamanı. Çıktı: aktif banner'lar,
/// filtrelenmiş ve boşalınca düşürülmüş raflar, tür çip listesi. SwiftUI View bunu doğrudan çizer;
/// @Observable model bunu hesaplar ama tüm karar burada izole test edilir.
///
/// Tür filtresi istemci tarafında uygulanır (SS-071/074): `GET /discover` tür parametresi almadığı
/// için (ContentKit `CatalogServicing.discover()` argümansızdır) "raf yapısı korunur, içerik
/// filtrelenir" davranışı (02 §4.10) burada raf-içi filtrelemeyle karşılanır.
public struct KesfetComposition: Equatable, Sendable {
    /// Türetilmiş raf: kimlik + tür + başlık + (filtrelenmiş) diziler.
    public struct Shelf: Equatable, Sendable, Identifiable {
        public let id: String
        public let kind: Collection.Kind
        public let title: String
        public let series: [Series]

        public init(id: String, kind: Collection.Kind, title: String, series: [Series]) {
            self.id = id
            self.kind = kind
            self.title = title
            self.series = series
        }

        /// Top-10 rafı özel sıra numarası düzenine sahiptir (02 §4.10: numara poster'ın soluna taşar).
        public var showsRankBadges: Bool {
            kind == .top10
        }
    }

    /// Gösterim penceresi aktif banner'lar (05 §11: süresi geçmiş banner gösterilmez). Tür filtresi
    /// aktifken banner'lar gizlenir — banner'a tür meta'sı iliştirilmediği için filtreye atfedilemez.
    public let banners: [Banner]
    /// Filtre uygulandıktan sonra en az bir dizi kalan raflar, backend sırasında.
    public let shelves: [Shelf]
    /// Tür çip listesi ("Tümü" hariç; View başa "Tümü" ekler). Rafardaki dizilerin türlerinin
    /// ilk-görülme sırasına göre tekilleştirilmiş birleşimi.
    public let availableGenres: [Genre]
    /// Seçili tür filtresi; nil = "Tümü".
    public let selectedGenreID: String?

    public init(banners: [Banner], shelves: [Shelf], availableGenres: [Genre], selectedGenreID: String?) {
        self.banners = banners
        self.shelves = shelves
        self.availableGenres = availableGenres
        self.selectedGenreID = selectedGenreID
    }

    /// Vitrin tamamen boş mu (hiç raf yok).
    public var isEmpty: Bool {
        shelves.isEmpty
    }

    /// Tür filtresi aktif mi.
    public var hasActiveFilter: Bool {
        selectedGenreID != nil
    }

    /// Filtre sonucu boş durumu (02 §4.10: "Bu türde henüz içerik yok" + filtre temizleme CTA).
    /// Filtre yokken boşluk = veri yokluğu (Hata/başka durum), filtre boşluğu değildir.
    public var isFilteredEmpty: Bool {
        isEmpty && hasActiveFilter
    }

    /// Filtre-öncesi tür çip listesini korurken içeriği filtreler — böylece boş sonuçta bile
    /// kullanıcı başka türe / "Tümü"'ye geçebilir (çip listesi kaybolmaz, 02 §4.10).
    public static func compose(content: DiscoverContent, selectedGenreID: String?, now: Date) -> KesfetComposition {
        let genres = availableGenres(in: content)
        let activeBanners = content.banners.filter { $0.isActive(at: now) }
        // Filtre aktifken banner gizli (tür atfı yapılamaz); "Tümü"'de aktif banner'lar görünür.
        let banners = selectedGenreID == nil ? activeBanners : []
        let shelves = content.collections.compactMap { collection -> Shelf? in
            let filtered = filterSeries(collection.seriesList, byGenreID: selectedGenreID)
            guard !filtered.isEmpty else { return nil }
            return Shelf(id: collection.id, kind: collection.kind, title: collection.title, series: filtered)
        }
        return KesfetComposition(
            banners: banners,
            shelves: shelves,
            availableGenres: genres,
            selectedGenreID: selectedGenreID
        )
    }

    /// İçerik yokken (henüz yüklenmedi / temizlendi) boş kompozisyon; seçili filtre korunur.
    public static func empty(selectedGenreID: String?) -> KesfetComposition {
        KesfetComposition(banners: [], shelves: [], availableGenres: [], selectedGenreID: selectedGenreID)
    }

    private static func filterSeries(_ series: [Series], byGenreID genreID: String?) -> [Series] {
        guard let genreID else { return series }
        return series.filter { $0.genres.contains { $0.id == genreID } }
    }

    /// Tüm rafardaki dizilerin türlerinin ilk-görülme sırasına göre tekilleştirilmiş birleşimi.
    private static func availableGenres(in content: DiscoverContent) -> [Genre] {
        var seen = Set<String>()
        var result: [Genre] = []
        for collection in content.collections {
            for series in collection.seriesList {
                for genre in series.genres where seen.insert(genre.id).inserted {
                    result.append(genre)
                }
            }
        }
        return result
    }
}
