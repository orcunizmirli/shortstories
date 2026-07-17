import AnalyticsKit
import AppFoundation

/// `ab_variants` ortak boyutunu (08 §1.3 / §7.3) HER feature analitik event'ine ekleyen dekoratör.
/// Canlı `AppAnalyticsTracker`'ı sarar; oturumda maruz kalınan atamalardan üretilen kanonik string'i
/// (`ExperimentClient.abVariantsParameter()`) parametre olarak enjekte eder. Feature model'leri bunu
/// `dependencies.analytics` YERİNE alır → o oturumdaki aktif varyantlar tüm event'lere birlikte düşer
/// (deney boyutu analitik'e; SS-154).
///
/// `ab_exposure` bu dekoratörden GEÇMEZ: `ExperimentClient` exposure'ı BASE tracker'a doğrudan emit eder
/// (§7.3 "diğer event'lere ortak boyut" — exposure zaten `exp_key`/`variant` taşır, kendini çoğaltmaz).
///
/// Concurrency: base tracker `Sendable`, `ab_variants` üretimi `@Sendable` kilitli okuma
/// (`ExperimentClient` `@unchecked Sendable`); tip immutable → `Sendable`.
public struct ExperimentDimensionTracker: AnalyticsTracking {
    private let base: any AnalyticsTracking
    private let abVariants: @Sendable () -> String

    public init(base: any AnalyticsTracking, abVariants: @escaping @Sendable () -> String) {
        self.base = base
        self.abVariants = abVariants
    }

    public func track(_ name: String, parameters: [String: AnalyticsValue]) {
        let variants = abVariants()
        // Henüz maruz kalınan atama yoksa event'i değiştirmeden geçir (boş boyut eklenmez).
        guard !variants.isEmpty else {
            base.track(name, parameters: parameters)
            return
        }
        var enriched = parameters
        // Çağıran açıkça `ab_variants` verdiyse EZME (feature-özgü override saygı görür).
        if enriched[ABVariants.parameterKey] == nil {
            enriched[ABVariants.parameterKey] = .string(variants)
        }
        base.track(name, parameters: enriched)
    }
}
