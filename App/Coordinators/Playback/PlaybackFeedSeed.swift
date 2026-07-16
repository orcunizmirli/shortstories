import AppFoundation
import ContentKit
import Foundation
import PlayerKit

/// SS-062/065 bağlamsal oynatma seed'i: çözülmüş `FeedEntry` + entry'yi çözülebilir kılan feed
/// öğeleri. `HomeCoordinator` bunu `PlayerFeedViewModel.feedState`e akıtır ve
/// `makePlayerFeedView()` içinde `PlayerFeedView(entry:)` ile PlayerKit'e verir; PlayerKit seed'i
/// bir kez tüketip doğru kart/konumdan İLK aktivasyonu yapar (04 §8.6 auto-advance değişmez).
struct PlaybackFeedSeed: Equatable, Sendable {
    /// Feed'in başlayacağı içerik/konum (PlayerKit seed'i).
    let entry: FeedEntry
    /// Seed'in çözüleceği feed öğeleri (dizinin doğal bölüm sırası). Boş feed'de seed
    /// çözülemez; bu yüzden hedef bölümü içeren öğeler App tarafında burada kurulur.
    let items: [FeedItem]
}

/// SS-062 SAF intent→feed-entry eşlemesi (yan etkisiz): `HomeCoordinator.PlaybackIntent`
/// (deep-link `.play`/`.episode`, DiziDetay/Listem "oynat", Ana Sayfa "devam et") → PlayerKit
/// `FeedEntry`. Bölüm-numarası → bölüm-ID çözümü ve feed öğesi kurulumu da burada; test bu saf
/// katmanı hedefler (koordinatör/katalog G/Ç ayrı `PlaybackFeedResolver`'da).
enum PlaybackIntentMapper {
    /// Intent → hedef bölüm ID'si. Öncelik: (1) önceden çözülmüş `episodeID` (Ana Sayfa/Listem
    /// "devam et" — kayıt bölümü doğrudan taşır); (2) `episodeNumber` bölüm listesinde 1-tabanlı
    /// `index` ile eşlenir (deep-link/DiziDetay); (3) ikisi de yoksa nil → çağıran "ilk oynatılabilir"
    /// bölümü seçer (çıplak dizi `.play`).
    static func targetEpisodeID(
        for intent: HomeCoordinator.PlaybackIntent,
        in episodes: [Episode]
    ) -> EpisodeID? {
        if let episodeID = intent.episodeID {
            return episodeID
        }
        if let number = intent.episodeNumber {
            return episodes.first(where: { $0.index == number })?.id
        }
        return nil
    }

    /// Intent + çözülmüş bölüm → `FeedEntry`. Konum negatif→0 kırpması ve süreye kırpma
    /// `FeedEntry`/`FeedSeedPolicy` içindedir; burada yalnız değer taşınır.
    static func makeEntry(
        for intent: HomeCoordinator.PlaybackIntent,
        resolvedEpisodeID: EpisodeID?
    ) -> FeedEntry {
        FeedEntry(
            seriesID: intent.seriesID,
            episodeID: resolvedEpisodeID,
            startPositionSeconds: intent.startPositionSec
        )
    }

    /// Ana Sayfa "kaldığın yerden devam" kaydından intent (SS-065). Bölüm ID'si DOĞRUDAN taşınır
    /// (numara lookup'ı yok — kayıt zaten bölümü bilir), pozisyon "kaldığın yer"dir.
    static func continueIntent(
        seriesID: SeriesID,
        episodeID: EpisodeID,
        positionSec: Double
    ) -> HomeCoordinator.PlaybackIntent {
        HomeCoordinator.PlaybackIntent(
            seriesID: seriesID,
            episodeID: episodeID,
            startPositionSec: positionSec
        )
    }

    /// Bölüm → feed öğesi. `progress` bilinçli nil bırakılır: başlangıç konumu tek kanaldan,
    /// `FeedEntry.startPositionSeconds` override'ıyla taşınır (SS-065). Öğeye bayat bir devam
    /// kaydı iliştirmek "İzlemeye Başla" (konum 0) niyetini kırar (baştan yerine ortadan başlar).
    static func makeFeedItem(series: Series, episode: Episode) -> FeedItem {
        FeedItem(
            id: "seed-\(episode.id.rawValue)",
            type: .episode,
            episode: episode,
            series: series,
            progress: nil,
            reason: nil
        )
    }
}

/// SS-062 bağlamsal oynatma çözümleyicisi: `PlaybackIntent` → `PlaybackFeedSeed` (katalog G/Ç ile).
/// Hedef bölümü bölüm listesinden çözer (ilk sayfada değilse sınırlı sayfalama ile arar) ve dizinin
/// doğal sıralı bölümlerini feed öğesi olarak kurar. SAF eşleme `PlaybackIntentMapper`'dadır; bu tip
/// yalnız katalog fetch orkestrasyonunu yapar (nonisolated → koordinatörden ayrı test edilir).
struct PlaybackFeedResolver: Sendable {
    let catalog: any CatalogServicing
    /// Hedef bölüm ilk sayfada değilse taranacak azami bölüm-listesi sayfası (sınırlı G/Ç; F1
    /// dizileri kısa — hedef hemen daima ilk sayfalarda). Aşılırsa seed mevcut öğelere düşer.
    var maxEpisodePages = 8

    func resolve(_ intent: HomeCoordinator.PlaybackIntent) async -> PlaybackFeedSeed? {
        guard let series = try? await catalog.seriesDetail(id: intent.seriesID) else { return nil }
        let episodes = await loadEpisodes(seriesID: intent.seriesID, matching: intent)
        guard !episodes.isEmpty else { return nil }
        let resolvedID = PlaybackIntentMapper.targetEpisodeID(for: intent, in: episodes)
            ?? firstPlayable(in: episodes)?.id
        let items = episodes.map { PlaybackIntentMapper.makeFeedItem(series: series, episode: $0) }
        let entry = PlaybackIntentMapper.makeEntry(for: intent, resolvedEpisodeID: resolvedID)
        return PlaybackFeedSeed(entry: entry, items: items)
    }

    /// Bölümleri sayfa sayfa toplar; hedef (episodeID/episodeNumber) bulununca durur. Çıplak dizi
    /// `.play`'inde ilk sayfa yeter. Hata/son sayfa → eldekiyle döner.
    private func loadEpisodes(seriesID: SeriesID, matching intent: HomeCoordinator.PlaybackIntent) async -> [Episode] {
        var accumulated: [Episode] = []
        var cursor: String?
        for _ in 0 ..< max(1, maxEpisodePages) {
            guard let page = try? await catalog.episodes(seriesId: seriesID, cursor: cursor) else { break }
            accumulated.append(contentsOf: page.items)
            if targetSatisfied(by: accumulated, intent: intent) {
                break
            }
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return accumulated
    }

    /// Hedef bölüm eldeki bölümlerde MEVCUT mu (sayfalamayı durdurma kararı). Çıplak intent'te
    /// (hedef yok) ilk sayfa yeterlidir.
    private func targetSatisfied(by episodes: [Episode], intent: HomeCoordinator.PlaybackIntent) -> Bool {
        if let episodeID = intent.episodeID {
            return episodes.contains { $0.id == episodeID }
        }
        if let number = intent.episodeNumber {
            return episodes.contains { $0.index == number }
        }
        return true
    }

    private func firstPlayable(in episodes: [Episode]) -> Episode? {
        episodes.first(where: { $0.access.isPlayableWithoutUnlock }) ?? episodes.first
    }
}
