/// Feature'ların deney varyantını okuduğu port (docs/08 §7.3). Bir varyant İLK okunduğunda
/// exposure otomatik tetiklenir (oturum başına idempotent) — feature ayrıca event atmaz.
///
/// R-kuralları: bu port `AnalyticsKit`'te yaşar; feature'lar R4 üzerinden import eder ve
/// kompozisyon kökünde (`ShortSeriesApp`) canlı `ExperimentClient` init-injection ile verilir
/// (feature-özgü yüzey `Dependencies` konteynerine giremez — 03 §4.1).
public protocol ExperimentReading: Sendable {
    /// Verilen deneyde bu kullanıcının varyantı. İlk okumada `ab_exposure` tetiklenir.
    /// Tanım yoksa / deney aktif değilse / kullanıcı atanmadıysa `nil` (kontrol davranışı).
    func variant(for experimentKey: String) -> ExperimentVariant?
}
