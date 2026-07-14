import ContentKit
import Foundation

/// Kesfet layout'unun ETag/TTL cache anlık görüntüsü (05 §7.2 stale-while-revalidate).
/// `DiscoverContent` + kaydedilme zamanı; tazelik kararı `CacheFreshness`'tedir.
public struct CachedDiscover: Sendable, Equatable {
    public let content: DiscoverContent
    public let storedAt: Date

    public init(content: DiscoverContent, storedAt: Date) {
        self.content = content
        self.storedAt = storedAt
    }
}

/// Cache tazelik kararı — saf (05 §7.2). SWR'de bayat içerik yine gösterilir; TTL yalnız
/// yükleme anında gereksiz ağ turunu (çok taze cache) atlamak için kullanılır. Pull-to-refresh
/// tazeliği yok sayar (her zaman revalidate).
public enum CacheFreshness {
    /// Varsayılan Kesfet TTL'i — 05 §7.2 `/discover` sunucu sözleşmesi: `private, max-age=600`
    /// (stale-while-revalidate). `/series` değeri olan 300 ile karıştırılmamalı.
    public static let discoverTTL: Duration = .seconds(600)

    /// `storedAt`den bu yana geçen süre `ttl`den küçükse taze. Gelecek tarihli `storedAt`
    /// (saat kayması) taze sayılır.
    public static func isFresh(storedAt: Date, ttl: Duration, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(storedAt)
        guard elapsed >= 0 else { return true }
        return elapsed < ttl.seconds
    }
}

private extension Duration {
    var seconds: Double {
        let (secs, attos) = components
        return Double(secs) + Double(attos) / 1_000_000_000_000_000_000
    }
}

/// Kesfet'in oturum-içi durumu: layout cache'i + seçili tür filtresi (SS-071/074).
/// Model'in yaşam döngüsünden BAĞIMSIZ tutulur (App tarafından sekme oturumu boyunca yaşayan
/// tek instance olarak enjekte edilir) — böylece Kesfet stack'inde ileri/geri gidilse ve model
/// yeniden yaratılsa bile hem cache hem tür filtresi korunur ("oturum-içi filtre kalıcılığı").
/// @MainActor: yalnız SwiftUI sunum katmanından erişilir.
@MainActor
public final class DiscoverSessionStore {
    public private(set) var cached: CachedDiscover?
    /// Seçili tür filtresi; nil = "Tümü" (oturum boyunca kalıcı).
    public var selectedGenreID: String?

    public init(cached: CachedDiscover? = nil, selectedGenreID: String? = nil) {
        self.cached = cached
        self.selectedGenreID = selectedGenreID
    }

    public func save(_ content: DiscoverContent, at date: Date) {
        cached = CachedDiscover(content: content, storedAt: date)
    }
}
