import Foundation

/// Exponential backoff + jitter retry politikası (03 §8.3 tablosu).
///
/// | Durum | Davranış |
/// |---|---|
/// | 5xx, timeout, bağlantı kopması | 0.5 → 1 → 2 sn backoff (nominal; maks 3 retry). Yalnız idempotent istekler. |
/// | 429 | Backoff. (`Retry-After` header desteği SS-020'de gelir — bilinçli F0 sadeleştirmesi.) |
/// | 401 | Retry yok — refresh akışı (03 §8.2, SS-021). |
/// | Diğer 4xx | Retry yok; `AppError` olarak yüzer. |
/// | Cüzdan/satın alma uçları | `.never` — idempotency-key ile kullanıcı tetikli yeniden deneme. |
/// | Feed/prefetch istekleri | `.never` — tek deneme, başarısızlık sessizce loglanır. |
public struct RetryPolicy: Sendable, Equatable {
    /// İlk denemeden SONRAKİ maksimum retry sayısı (toplam istek = 1 + maxRetries).
    public var maxRetries: Int
    public var baseDelay: Duration
    public var multiplier: Double
    /// Hesaplanan nominal gecikmeye uygulanan rastgele çarpan aralığı.
    public var jitter: ClosedRange<Double>

    public init(
        maxRetries: Int,
        baseDelay: Duration = .milliseconds(500),
        multiplier: Double = 2.0,
        jitter: ClosedRange<Double> = 0.8 ... 1.2
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.jitter = jitter
    }

    /// Varsayılan politika: nominal 0.5 / 1 / 2 sn, maks 3 retry.
    public static let `default` = RetryPolicy(maxRetries: 3)

    /// Otomatik retry yok (cüzdan/satın alma uçları; feed/prefetch tek deneme).
    public static let never = RetryPolicy(maxRetries: 0)

    /// `attempt` 0 tabanlıdır: 0 = ilk başarısız denemeden sonra.
    /// Retry hakkı bittiyse ya da hata retryable değilse `nil` döner (çağıran hatayı fırlatır).
    public func delay(afterAttempt attempt: Int, error: AppError) -> Duration? {
        guard error.isRetryable, attempt >= 0, attempt < maxRetries else { return nil }
        let nominal = baseDelaySeconds * pow(multiplier, Double(attempt))
        return .seconds(nominal * Double.random(in: jitter))
    }

    private var baseDelaySeconds: Double {
        let components = baseDelay.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
