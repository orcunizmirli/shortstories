import Foundation

/// SS-024 / 08 §7.3 — maruz kalınan (`ab_exposure`) deney anahtarlarını OTURUMLAR ARASI kalıcı kılan
/// App-katmanı deposu. `ExperimentClient` `previouslyExposed` tohumunu buradan alır → DÖNEN kullanıcı
/// için `first_exposure` yanlışça `true` DÜŞMEZ (aksi halde her soğuk açılış "ilk maruz kalma" sayılır →
/// win-back/funnel KPI kalıcı ŞİŞER). scenePhase `.background`'da `merge(client.exposedExperimentKeys)`
/// birikimli yazar. Deney atamaları deviceID-scoped (hesap-bağımsız — `makeConfigGraph` `userID: deviceID`)
/// olduğundan tek global anahtar doğru kapsamdır; hesap değişimi exposure geçmişini sıfırlamaz.
///
/// `load()` hiç yazılmadıysa boş küme döner (ilk açılış → tümü `first_exposure=true`). `UserDefaults`
/// thread-safe olduğundan `@unchecked Sendable` güvenlidir. `UserDefaultsLastSeenStreakStore` deseni.
final class UserDefaultsExposedExperimentsStore: @unchecked Sendable {
    /// 03 §9 UserDefaults ad uzayı — AnalyticsKit deney-exposure geçmişi anahtarı.
    static let key = "analytics.exposed_experiments"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Önceki oturumlarda maruz kalınmış deney anahtarları (yoksa boş — ilk açılış, kırılma yok).
    func load() -> Set<String> {
        guard let stored = defaults.array(forKey: Self.key) as? [String] else { return [] }
        return Set(stored)
    }

    /// Bu oturumda maruz kalınan anahtarları mevcut kümeye BİRLEŞTİRİR (idempotent, birikimli). Boş
    /// girdi yazma YAPMAZ (exposure alınmamış oturumda gereksiz disk I/O yok).
    func merge(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let merged = load().union(keys)
        defaults.set(Array(merged), forKey: Self.key)
    }
}
