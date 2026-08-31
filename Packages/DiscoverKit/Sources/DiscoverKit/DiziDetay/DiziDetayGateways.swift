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

/// Entitlement (VIP/kilit-açma) DEĞİŞİM sinyali portu (bug-hunt #2): DiziDetay açıkken unlock/VIP aktivasyon/
/// bitiş olursa erişim kümesi + CTA yeniden türetilir → kullanıcı ödediği bölümü bu ekrandan oynayabilir
/// (aksi halde CTA 🔒 kalıp zaten sahip olunan bölüm için UnlockSheet yeniden açılıyordu). Evi WalletKit
/// (`WalletStore.entitlementUpdates`); App void'e map eder. Anlık sorgu portu `EntitlementChecking` ayrıdır.
public protocol EntitlementChangeObserving: Sendable {
    /// Her emisyon "entitlement değişti, erişimi yeniden türet" sinyalidir (değerin kendisi taşınmaz).
    func entitlementChanges() -> AsyncStream<Void>
}
