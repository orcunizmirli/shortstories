import AppFoundation

/// ContentKit — Series/Episode modelleri, katalog & feed API istemcileri (KANON §4).
/// F1 kapsamı: SS-030…SS-035 (docs/09 §E4); modeller 05-veri-modeli-api.md sözleşmesiyle gelir.
/// `SeriesID`/`EpisodeID` bu pakette DEĞİL, AppFoundation/SharedTypes'ta yaşar (03 §4 R3).
public enum ContentKitModule {
    public static let name = "ContentKit"
}
