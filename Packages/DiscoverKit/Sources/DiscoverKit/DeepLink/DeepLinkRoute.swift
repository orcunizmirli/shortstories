import AppFoundation
import Foundation

/// Ödüller sekmesi deep link çapası (02 §8.3 `RewardsAnchor`).
public enum RewardsAnchor: String, Equatable, Sendable {
    case checkin
}

/// Listem sekmesi segment çapası (02 §8.2 `mylist?segment=`).
public enum MyListSegment: String, Equatable, Sendable {
    case favorites
    /// Rota parametresinde `continue` yazılır; `continue` Swift anahtar kelimesi
    /// olduğundan case adı `continueWatching`, rawValue korunur (§8.2).
    case continueWatching = "continue"
    case downloads
}

/// Uygulamanın tüm deep link / universal link hedeflerinin tipli karşılığı
/// (02 §8.3 `Route` iskeleti). DiscoverKit saf çözümleyicisi bu tipi üretir; App
/// koordinatörü kendi `Route`/coordinator kompozisyonuna bağlar (03 §3.2).
///
/// `series`/`episode`/`play` ID'leri `AppFoundation.SeriesID` taşır — bu tip
/// katman sınırından geçebilir (03 §4 R3) ve DiscoverKit ContentKit'e bağlıdır.
public enum DeepLinkRoute: Equatable, Sendable {
    case home
    case series(id: SeriesID)
    case episode(seriesId: SeriesID, number: Int)
    case play(seriesId: SeriesID, startSeconds: Int?)
    case discover(genre: String?)
    case search(query: String?)
    case rewards(anchor: RewardsAnchor?)
    case coinStore(offer: String?)
    case vip(preselectedPlan: String?)
    case myList(segment: MyListSegment?)
    case profile
    case settings(section: String?)
    case notifications

    /// 02 §8.3 sözleşmesi: custom scheme + universal link path parser; bilinmeyen path → nil.
    public init?(url: URL) {
        guard let route = DeepLinkResolver.route(from: url) else { return nil }
        self = route
    }

    /// Analitik `route_type` parametresi (02 §8.4 kural 5: `deeplink_opened {route_type}`).
    public var analyticsType: String {
        switch self {
        case .home: "home"
        case .series: "series"
        case .episode: "episode"
        case .play: "play"
        case .discover: "discover"
        case .search: "search"
        case .rewards: "rewards"
        case .coinStore: "coin_store"
        case .vip: "vip"
        case .myList: "my_list"
        case .profile: "profile"
        case .settings: "settings"
        case .notifications: "notifications"
        }
    }
}
