import AppFoundation

/// Arama'nın açılış kaynağı (08 §3.3 `search_open.source`).
public enum AramaSource: String, Sendable, Equatable {
    case kesfet
    case deeplink
}

/// Arama intent sözleşmesi — App koordinatörü bağlar (02 §4.11). Zayıf referans, MainActor.
@MainActor
public protocol AramaDelegate: AnyObject {
    /// Öneri/sonuç kartı → `DiziDetay` push (§4.11).
    func aramaDidSelectSeries(_ seriesID: SeriesID)
    /// "İptal" → `Kesfet`'e döner (§4.11).
    func aramaRequestsDismiss()
}
