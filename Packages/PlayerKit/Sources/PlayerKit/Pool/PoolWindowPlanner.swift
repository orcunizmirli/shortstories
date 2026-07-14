import Foundation

/// Kaydırma yönü (PlayerKit-internal): pencere ve prefetch önceliği bu sinyale göre
/// döner (04 §5.2). Feed VC (sonraki dilim) UIScrollView'dan üretir.
enum ScrollDirection: Sendable, Equatable {
    case forward
    case backward

    var step: Int {
        self == .forward ? 1 : -1
    }
}

/// Havuz slot rolü (04 §3.3): aktif oynayan, warm (item yüklü + 1 sn buffer), idle boş.
enum SlotRole: Sendable, Equatable {
    case active
    case warm
    case idle
}

/// Index-etrafı pencere mantığının saf fonksiyonları (04 §3.2): yan etkisiz,
/// gerçek player olmadan test edilir.
enum PoolWindowPlanner {
    /// Öncelik sıralı hedef pencere: aktif → yön komşusu → ters komşu → yönde +2 →
    /// ters yönde -2 (4.–5. slot; 04 §3.2 tablosu). Feed sınırlarına kırpılır.
    static func desiredIndexes(
        activeIndex: Int,
        direction: ScrollDirection,
        poolSize: Int,
        episodeCount: Int
    ) -> [Int] {
        let step = direction.step
        // Rol pozisyonları havuz boyutuyla sınırlıdır; feed sınırında düşen pozisyon
        // BAŞKA indeksle doldurulmaz (04 §3.2 tablosu rol tanımıdır, doldurma değil).
        let rolePositions = [
            activeIndex,
            activeIndex + step,
            activeIndex - step,
            activeIndex + 2 * step,
            activeIndex - 2 * step
        ].prefix(poolSize)
        var seen = Set<Int>()
        return rolePositions.filter { (0 ..< episodeCount).contains($0) && seen.insert($0).inserted }
    }

    /// Geri alınacak slot (04 §3.3 kural 3): önce boş slot; yoksa aktif feed indeksine
    /// EN UZAK slot (LRU-benzeri). Aktif slot ASLA geri alınmaz. Eşit uzaklıkta ilk
    /// aday seçilir (deterministik). `excluding`: authorize uçuşundaki claim'li
    /// slot'lar — eşzamanlı acquire onları geri alamaz (claim-önce-await korkuluğu).
    static func reclaimableSlot(
        feedIndexes: [Int?],
        activeSlot: Int?,
        activeFeedIndex: Int?,
        excluding claimedSlots: Set<Int> = []
    ) -> Int? {
        let candidates = feedIndexes.indices.filter { $0 != activeSlot && !claimedSlots.contains($0) }
        if let empty = candidates.first(where: { feedIndexes[$0] == nil }) {
            return empty
        }
        guard let activeFeedIndex else { return candidates.first }
        var best: Int?
        var bestDistance = -1
        for slot in candidates {
            let distance = feedIndexes[slot].map { abs($0 - activeFeedIndex) } ?? Int.max
            // strict >: eşit uzaklıkta İLK aday kazanır (deterministik).
            if distance > bestDistance {
                best = slot
                bestDistance = distance
            }
        }
        return best
    }
}
