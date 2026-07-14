import Foundation

/// LRU karar mantığının taşıma-bağımsız kayıt görüntüsü. `CachedAssetRecord`
/// (AppFoundation) izlenmişlik bilgisi taşımadığından store, izlenmişlik kümesini
/// bu görüntüde birleştirir (04 §7.2: izlenmiş bölümler eviction'da önceliklidir).
struct CacheRecordSnapshot: Sendable, Equatable {
    let url: URL
    let sizeInBytes: Int64
    let lastAccessAt: Date
    let isWatched: Bool
}

/// ~200 MB LRU eviction kararları — SAF (04 §7.2): yan etkisiz, dosya sistemi yok.
enum CacheEvictionPlanner {
    /// Bütçe aşımı: (mevcut + gelen) − bütçe; negatifse 0.
    static func bytesToFree(totalSizeInBytes: Int64, incomingBytes: Int64, budgetBytes: Int64) -> Int64 {
        max(0, totalSizeInBytes + incomingBytes - budgetBytes)
    }

    /// Kurban seçimi: önce izlenmiş (tamamlanmış) bölümler, kendi içlerinde en eski
    /// erişim önce; toplam boyut ihtiyacı karşılayana dek.
    static func selectVictims(candidates: [CacheRecordSnapshot], bytesToFree: Int64) -> [CacheRecordSnapshot] {
        guard bytesToFree > 0 else { return [] }
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.isWatched != rhs.isWatched {
                return lhs.isWatched // izlenmiş önce
            }
            return lhs.lastAccessAt < rhs.lastAccessAt
        }
        var freed: Int64 = 0
        var victims: [CacheRecordSnapshot] = []
        for candidate in ordered {
            guard freed < bytesToFree else { break }
            victims.append(candidate)
            freed += candidate.sizeInBytes
        }
        return victims
    }
}

/// Ön-indirme uygunluğu — SAF (04 §7.2): yalnız Wi-Fi'da, kilitli/entitlement'sız
/// asla (04 §9.1 kural 4), zaten cache'liyse tekrar indirme yok.
enum CachePreloadPolicy {
    static func shouldPreload(
        isPlayableWithoutUnlock: Bool,
        hasEntitlement: Bool,
        network: NetworkCondition,
        isAlreadyCached: Bool
    ) -> Bool {
        guard isPlayableWithoutUnlock || hasEntitlement else { return false }
        guard network.interface == .wifi, !network.isConstrained else { return false }
        return !isAlreadyCached
    }
}
