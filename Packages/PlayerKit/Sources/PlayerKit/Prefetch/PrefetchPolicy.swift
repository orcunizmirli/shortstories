import Foundation

/// Prefetch bütçesi (04 §5.1 kanon): ~500 KB veya ilk 2 sn — hangisi önce dolarsa.
/// HLS'de pratikte master playlist + ilk media playlist + ilk 1–2 segment demektir.
struct PrefetchBudget: Sendable, Equatable {
    let maxBytes: Int64
    let maxSeconds: Double

    static let standard = PrefetchBudget(maxBytes: 500 * 1024, maxSeconds: 2)
}

/// Prefetch hedef seçimi — SAF politika (04 §5): hangi indeksler, hangi bütçe,
/// yön farkındalığı, hücresel davranış. Yan etkisiz; PrefetchController uygular.
enum PrefetchPolicy {
    /// İki swipe arası bu eşiğin altındaysa ara indeksler atlanır (04 §5.2).
    static let fastFlickThresholdSeconds: Double = 0.3

    struct Context: Sendable, Equatable {
        var activeIndex: Int
        var direction: ScrollDirection
        var poolSize: Int
        var episodeCount: Int
        /// Bu kullanıcı için oynatılamayan (kilitli) feed indeksleri — ısındırılmaz
        /// (04 §9.1 kural 4).
        var lockedIndexes: Set<Int>
        var network: NetworkCondition
        var isDataSaverEnabled: Bool
        /// Son iki pencere değişimi arasındaki süre; nil = ilk pencere.
        var secondsSinceLastSwipe: Double?
    }

    struct Plan: Sendable, Equatable {
        /// Öncelik sıralı prefetch hedefleri (feed indeksi). Boş = prefetch durdu.
        var targetIndexes: [Int]
        var budget: PrefetchBudget
    }

    static func plan(_ context: Context) -> Plan {
        // Veri tasarrufu modu veya iOS Low Data Mode: prefetch TAMAMEN durur (04 §5.3).
        guard !context.isDataSaverEnabled, !context.network.isConstrained else {
            return Plan(targetIndexes: [], budget: .standard)
        }

        let step = context.direction.step
        var preferenceOrder = [context.activeIndex + step]

        let isFastFlick = context.secondsSinceLastSwipe.map { $0 < fastFlickThresholdSeconds } ?? false
        // 4.–5. slotlu havuz yönde bir adım önde gider; hızlı flick'te atlanır (04 §5.2).
        if context.poolSize >= 4, !isFastFlick {
            preferenceOrder.append(context.activeIndex + 2 * step)
        }

        let targets = preferenceOrder.filter { index in
            (0 ..< context.episodeCount).contains(index) && !context.lockedIndexes.contains(index)
        }
        return Plan(targetIndexes: targets, budget: .standard)
    }
}

/// Bitrate tavanı politikası (04 §6.3): veri tasarrufu 480p (kanon), hücresel 720p
/// (remote config varsayılanı), Wi-Fi sınırsız — ABR karar verir.
enum BitrateCapPolicy {
    /// 480p rung tavanı (bps).
    static let dataSaverCap: Double = 800_000
    /// 720p rung tavanı (bps).
    static let cellularCap: Double = 1_400_000

    /// 0 = sınırsız (`preferredPeakBitRate = 0`).
    static func maxBitrate(network: NetworkCondition, isDataSaverEnabled: Bool) -> Double {
        if isDataSaverEnabled || network.isConstrained {
            return dataSaverCap
        }
        if network.interface == .cellular {
            return cellularCap
        }
        return 0
    }

    /// `VideoPlaying.setPeakBitRateCap` girdisi: nil = tavansız (Wi-Fi — ABR karar verir).
    static func peakBitRateCap(network: NetworkCondition, isDataSaverEnabled: Bool) -> Double? {
        let cap = maxBitrate(network: network, isDataSaverEnabled: isDataSaverEnabled)
        return cap == 0 ? nil : cap
    }
}
