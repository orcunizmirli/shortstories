import AppFoundation
import Foundation

/// `Listem` kartlarının katalog metadata'sı — SAF değer tipi. Repository kayıtları yalnız
/// ID + ilerleme taşır (`FavoriteRecord`/`WatchProgressRecord`); poster/başlık/bölüm no gibi
/// görüntüleme verisi katalogdan JOIN edilir.
public struct LibrarySeriesInfo: Sendable, Equatable, Identifiable {
    public let id: SeriesID
    public let title: String
    /// 2:3 poster (imzasız public görsel); View yükler (DS bileşenleri hazır `Image` alır).
    public let coverURL: URL
    /// `false` = dizi yayından kalktı — kart soluk + "yayında değil" (02 §4.12 edge case).
    public let isAvailable: Bool

    public init(id: SeriesID, title: String, coverURL: URL, isAvailable: Bool) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.isAvailable = isAvailable
    }
}

/// `Listem` görüntüleme JOIN portu (SS-120). App kompozisyonu bunu ContentKit
/// `CatalogServicing` (+ SS-023 katalog cache) üzerine bağlar; LibraryKit yalnız bu dar
/// yüzeyi görür (offline'da cache'ten döner — Listem çevrimdışı tam işlevseldir, 02 §4.12).
/// Kaldırılmış/bulunamayan diziler sözlükten DÜŞER (çağıran `isAvailable=false` varsayar).
public protocol LibraryCatalogReading: Sendable {
    /// Verilen dizilerin özetleri (bulunamayanlar sonuçta yer almaz).
    func seriesInfo(ids: [SeriesID]) async -> [SeriesID: LibrarySeriesInfo]

    /// Bölüm ID'lerinin 1 tabanlı numaraları ("Bölüm 7" etiketi); bilinmeyen ID sözlükte yoktur.
    func episodeNumbers(ids: [EpisodeID]) async -> [EpisodeID: Int]
}
