import AppFoundation
import ContentKit

/// Kesfet intent sözleşmesi — App koordinatörü (DiscoverCoordinator) bağlar (02 §2.3, §4.10).
/// Zayıf referans, MainActor (SwiftUI sunum katmanı). DiscoverKit somut koordinatöre değil bu
/// protokole bağlanır; testler spy ile koşar.
@MainActor
public protocol KesfetDelegate: AnyObject {
    /// Kart/koleksiyon → `DiziDetay` push (kapak matched-geometry geçişi çağıranındır).
    func kesfetDidSelectSeries(_ seriesID: SeriesID, shelfID: String?)
    /// Banner action'ı çözülmüş rota olarak (dizi/koleksiyon veya kampanya deep link'i, ör.
    /// `shortseries://store/coins`). Rota koordinatörün mevcut Route mekanizmasına gider (§4.10).
    func kesfetDidOpenRoute(_ route: DeepLinkRoute)
    /// Üst arama çubuğu butonu → `Arama` push (klavye orada açılır, §4.10).
    func kesfetRequestsSearch()
    /// Raf başlığı "Tümü" → dikey ızgara sayfası (aynı stack'te push, §4.10).
    func kesfetDidSelectSeeAll(collectionID: String, title: String)
}
