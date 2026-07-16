import AppFoundation
import DiscoverKit
import Foundation

/// Sekme `NavigationStack`'lerinin paylaşılan tip-güvenli push hedefleri (03 §3.2). Her sekme
/// koordinatörü kendi `path`'ini bu enum ile sürer; hedef view'ı sahip koordinatör kurar
/// (delegate = koordinatörün kendisi). Feature'lar bu tipi görmez — App-içi navigasyon dilidir.
enum AppRoute: Hashable {
    /// Dizi vitrini (Keşfet/Arama/Listem stack'lerinde push). `source` analitik/menşe içindir.
    case diziDetay(seriesID: SeriesID, source: DiziDetaySource)
    /// Arama ekranı (Keşfet stack'inde push; klavye orada açılır). `query` deep link'ten (02 §8.2
    /// `search?q=`) gelen ön-doldurma sorgusudur — nil ise boş açılır.
    case arama(query: String?)
    /// Ayarlar (Profil stack'inde push).
    case ayarlar

    // Hashable için DiziDetaySource'u rawValue ile taşırız (enum: String → otomatik Hashable).
}

/// Deep link menşei (02 §8.4 kural 5 `deeplink_opened.source` enum'u). Analitik `source`
/// parametresini besler; `internal` Swift anahtar kelimesi olduğundan case adı `appInternal`,
/// rawValue "internal" korunur.
enum DeepLinkSource: String {
    case push
    case universal
    case qr
    case appInternal = "internal"
}
