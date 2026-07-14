import AppFoundation
import Foundation

/// Prefetch bayt/süre ölçüm kancası (04 §13.1 prefetch sayaçları, SS-047 devri).
///
/// F1 yaklaşımı: ısındırma bütçe TANIMI üzerinden yaklaşık kaydedilir (~500 KB /
/// ilk 2 sn — 04 §5.1); gerçek ağ trafiği sayacı (access log / URLSession metrics)
/// SS-041 buffer politikası doğrulamasıyla birlikte gelir. Debug HUD (04 §13.3) ve
/// prefetch isabet oranı bu kaydın tüketicileridir.
protocol PrefetchMeasuring: Sendable {
    func recordWarmupCompleted(
        episodeID: EpisodeID,
        approximateBytes: Int64,
        approximateSeconds: Double
    ) async
}

/// Varsayılan biriktirici: tamamlanan ısındırmaların yaklaşık bayt/süre toplamını
/// tutar (PlayerKit-internal; dışa metrik yüzeyi SS-047'nin sonraki dilimindedir).
actor PrefetchMeasurementLog: PrefetchMeasuring {
    struct Entry: Sendable, Equatable {
        let episodeID: EpisodeID
        let approximateBytes: Int64
        let approximateSeconds: Double
    }

    private(set) var entries: [Entry] = []

    var totalApproximateBytes: Int64 {
        entries.reduce(0) { $0 + $1.approximateBytes }
    }

    func recordWarmupCompleted(
        episodeID: EpisodeID,
        approximateBytes: Int64,
        approximateSeconds: Double
    ) {
        entries.append(Entry(
            episodeID: episodeID,
            approximateBytes: approximateBytes,
            approximateSeconds: approximateSeconds
        ))
    }
}
