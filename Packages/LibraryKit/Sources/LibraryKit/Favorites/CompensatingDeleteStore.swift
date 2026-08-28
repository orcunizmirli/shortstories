import AppFoundation
import Foundation

/// Telafi-DELETE niyetlerinin DURABLE deposu (audit MEDIUM: favorite-sync-loss / tombstone-dedup).
///
/// `FavoritesService.compensatingDeletes` bellek-içi bir `Set<SeriesID>`'ti: bir eklemenin PUT'u
/// uçarken araya giren kaldırma sunucuda HAYALET favori bırakır → telafi DELETE gerekir. Bu niyet
/// yalnız bellekteyken, DELETE gönderilmeden UYGULAMA ÖLDÜRÜLÜRSE (arka planda kill / crash) niyet
/// kaybolur; yerel `pendingAdd` zaten silindiği için hiçbir senkron işlemi hayaleti temizlemez →
/// sunucuda kalıcı hayalet favori. Bu depo niyeti kalıcılaştırır; sonraki açılışta yüklenip
/// `synchronize()`'ın telafi-flush'ında gönderilir.
public protocol CompensatingDeleteStoring: Sendable {
    /// Kalıcılaştırılmış telafi-DELETE niyetlerini yükler (açılışta FavoritesService init'i çağırır).
    func load() -> Set<SeriesID>
    /// Güncel telafi-DELETE kümesini kalıcılaştırır (her mutasyondan sonra çağrılır).
    func save(_ ids: Set<SeriesID>)
}

/// Bellek-içi (KALICI DEĞİL) varsayılan — geriye-uyumluluk + testler. Üretim App composition'ı
/// `PreferencesCompensatingDeleteStore` enjekte eder (app-kill'e dayanıklı).
public final class InMemoryCompensatingDeleteStore: CompensatingDeleteStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<SeriesID>

    public init(_ initial: Set<SeriesID> = []) {
        ids = initial
    }

    public func load() -> Set<SeriesID> {
        lock.withLock { ids }
    }

    public func save(_ newIDs: Set<SeriesID>) {
        lock.withLock { ids = newIDs }
    }
}

/// `PreferencesStoring` destekli DURABLE depo. Küme, `SeriesID.rawValue`'ları JSON `[String]` olarak
/// tek bir tercih anahtarında saklanır (app-kill'e dayanıklı). Bozuk/eksik değer → boş küme (güvenli).
public final class PreferencesCompensatingDeleteStore: CompensatingDeleteStoring, @unchecked Sendable {
    private let preferences: any PreferencesStoring
    private let key = PreferenceKey(name: "favorites.compensating_deletes", default: "")

    public init(preferences: any PreferencesStoring) {
        self.preferences = preferences
    }

    public func load() -> Set<SeriesID> {
        let raw = preferences.value(for: key)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(rawValues.map { SeriesID($0) })
    }

    public func save(_ ids: Set<SeriesID>) {
        // Deterministik sıralı seri (sırasız Set → kararlı JSON; gereksiz yazma dalgalanması olmaz).
        let rawValues = ids.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(rawValues),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return
        }
        preferences.set(encoded, for: key)
    }
}
