import AppFoundation
import ContentKit

/// İzleme geçmişi okuma portu (SS-080 CTA türetimi). Evi `LibraryKit`tir (izleme geçmişi +
/// "devam et"); DiscoverKit LibraryKit'i import etmeden bu protokole bağlanır (R2). App
/// kompozisyonu somut istemciyi bağlar, testler fake ile koşar.
public protocol WatchHistoryReading: Sendable {
    /// Bu dizinin en güncel izleme ilerlemesi; hiç izlenmediyse nil.
    func latestProgress(forSeries seriesID: SeriesID) async -> WatchProgress?
}

/// Favori/listeye ekle portu (SS-081). Evi `LibraryKit` (`PUT/DELETE /me/favorites`, 05 §4.10);
/// DiscoverKit protokole bağlanır (R2). Toggle optimistiktir; hata durumunda model geri alır.
public protocol FavoritesGateway: Sendable {
    func isFavorite(_ seriesID: SeriesID) async -> Bool
    func setFavorite(_ isFavorite: Bool, seriesID: SeriesID) async throws
}
