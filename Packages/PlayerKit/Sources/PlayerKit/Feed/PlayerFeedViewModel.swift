import ContentKit
import Foundation
import Observation

/// Feed durumu value tipi (04 §2.4): `PlayerFeedViewController.apply(state:)`
/// diff'li uygular — `reloadData` YASAK (04 §14 T7). Sunucu sıralaması
/// otoritatiftir; istemci yalnız dedup eder (05 §2.12).
public struct FeedState: Sendable, Equatable {
    public var items: [FeedItem]

    public init(items: [FeedItem] = []) {
        self.items = items
    }
}

/// PlayerFeed görünüm modeli (04 §2.3): ContentKit feed'ini saran @Observable
/// durum sahibi. F1 bu diliminde durum taşıyıcıdır; feed API yükleme/sayfalama
/// bağlaması (SS-062'nin App tarafı) kompozisyon kökünde bu modele akar —
/// yeni sayfa `feedState.items`'a eklenir, köprü `apply(state:)` ile diff'ler.
@MainActor
@Observable
public final class PlayerFeedViewModel {
    public var feedState: FeedState

    public init(feedState: FeedState = FeedState()) {
        self.feedState = feedState
    }
}
