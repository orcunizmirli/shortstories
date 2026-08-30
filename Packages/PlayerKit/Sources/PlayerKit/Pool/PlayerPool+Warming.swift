import ContentKit
import Foundation

// MARK: - EpisodeWarming (PrefetchController'ın havuza dar köprüsü)

extension PlayerPool: EpisodeWarming {
    /// warm = prepareNext (tamamlandı/geçici-hata Bool'unu taşır → PrefetchController başarısız warm'ı
    /// "tamamlandı" saymaz, pencere-içi yeniden denenebilir).
    func warm(_ episode: Episode, atFeedIndex feedIndex: Int) async -> Bool {
        await prepareNext(episode, atFeedIndex: feedIndex)
    }
}
