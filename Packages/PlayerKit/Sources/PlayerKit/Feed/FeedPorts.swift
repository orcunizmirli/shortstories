import ContentKit
import Foundation

/// Direktörün havuza dar köprüsü (PlayerKit-internal): feed katmanı havuzu bu
/// arayüzden görür; testler kayıt tutan sahteyle koşar. Canlısı `PlayerPool`'dur —
/// tüm çağrılar `FeedPlaybackDirector` üzerinden SERİLEŞİR (feed VC tek kapı;
/// bilinen sınırlama: acquire reentrancy — 03 §7.3).
protocol FeedPlaybackPooling: Sendable {
    func activate(
        _ episode: Episode,
        atFeedIndex feedIndex: Int,
        resumePosition: Double?
    ) async throws -> PlaybackHandle
    func prepareNext(_ episode: Episode, atFeedIndex feedIndex: Int) async
    func recycle(keeping window: ClosedRange<Int>) async
    func drain(keepPlayers: Bool) async
}

extension PlayerPool: FeedPlaybackPooling {}

/// Direktörün prefetch denetleyicisine dar köprüsü (PlayerKit-internal).
protocol FeedPrefetching: Sendable {
    func windowChanged(
        activeIndex: Int,
        episodes: [Episode],
        direction: ScrollDirection,
        at now: Date
    ) async
    func cancelAll() async
}

extension PrefetchController: FeedPrefetching {}
