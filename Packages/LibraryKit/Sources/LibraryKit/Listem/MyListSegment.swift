/// `Listem` sekmesinin segmentleri (02 §4.12, KANON §3): Favoriler, Devam Et, İndirilenler.
/// İndirilenler Faz 3'e kadar bir feature flag ile gizlidir (02 §4.12: "İndirilenler Faz 3'e
/// kadar gizli — feature flag").
public enum MyListSegment: Int, CaseIterable, Sendable, Equatable {
    case favorites
    case continueWatching
    case downloads

    /// Analitik parametresi (08 §3 `mylist_segment_changed.segment` / `screen_view.segment`).
    public var analyticsValue: String {
        switch self {
        case .favorites: "favorites"
        case .continueWatching: "continue"
        case .downloads: "downloads"
        }
    }

    /// Görünür segmentler — SAF (02 §4.12): İndirilenler yalnız flag açıkken (Faz 3) görünür.
    /// Sıra kanoniktir: Favoriler → Devam Et → (İndirilenler).
    public static func visible(downloadsEnabled: Bool) -> [MyListSegment] {
        var segments: [MyListSegment] = [.favorites, .continueWatching]
        if downloadsEnabled {
            segments.append(.downloads)
        }
        return segments
    }
}
