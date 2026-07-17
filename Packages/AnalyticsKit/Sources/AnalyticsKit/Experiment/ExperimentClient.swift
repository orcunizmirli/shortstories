import AppFoundation
import Foundation

/// Canlı deney istemcisi (docs/08 §7.1 "AnalyticsKit / deney istemcisi"): katalog +
/// deterministik atama + idempotent exposure + `ab_variants` beslemesi.
///
/// Exposure sözleşmesi (§7.3): bir varyant İLK okunduğunda `ab_exposure` gönderilir
/// (atama anında DEĞİL); oturum başına deney başına 1 kez (idempotent). `first_exposure`
/// kullanıcının deneye ilk kez mi maruz kaldığını belirtir (önceki oturumlar tohumlanabilir).
public final class ExperimentClient: ExperimentReading, @unchecked Sendable {
    private let catalog: any ExperimentCatalogReading
    private let assigner: any ExperimentAssigning
    private let analytics: any AnalyticsTracking
    private let userID: String
    private let priorExposed: Set<String>

    private let lock = NSLock()
    private var exposedThisSession: Set<String> = []
    private var exposedVariants: [String: String] = [:]

    /// - Parameters:
    ///   - userID: Stabil kullanıcı kimliği (guest/linked `userID` veya deviceID). Atamanın
    ///     yapışkanlık temeli — oturumlar arası aynı olmalı.
    ///   - assigner: Atama stratejisi (varsayılan deterministik hash; server override enjekte edilebilir).
    ///   - previouslyExposed: Önceki oturumlarda exposure alınmış deney anahtarları. `first_exposure`
    ///     değerini doğru hesaplamak için (persist edilmişse) tohumlanır.
    public init(
        catalog: any ExperimentCatalogReading,
        assigner: any ExperimentAssigning = DeterministicExperimentAssigner(),
        analytics: any AnalyticsTracking,
        userID: String,
        previouslyExposed: Set<String> = []
    ) {
        self.catalog = catalog
        self.assigner = assigner
        self.analytics = analytics
        self.userID = userID
        priorExposed = previouslyExposed
    }

    public func variant(for experimentKey: String) -> ExperimentVariant? {
        guard let experiment = catalog.experiment(for: experimentKey) else { return nil }
        guard let variant = assigner.assignment(for: experiment, userID: userID) else { return nil }
        recordExposureIfNeeded(experimentKey: experiment.key, variantID: variant.id)
        return variant
    }

    /// Bu oturumda maruz kalınan atamaların kanonik `ab_variants` string'i (§7.3). Diğer
    /// event'lere ortak boyut olarak eklenir.
    public func abVariantsParameter() -> String {
        ABVariants.format(lock.withLock { exposedVariants })
    }

    /// Bu oturumda exposure alınmış deney anahtarları — app katmanı bir sonraki oturuma
    /// `previouslyExposed` olarak persist edebilir.
    public var exposedExperimentKeys: Set<String> {
        lock.withLock { exposedThisSession }
    }

    private func recordExposureIfNeeded(experimentKey: String, variantID: String) {
        let shouldEmit: Bool = lock.withLock {
            exposedVariants[experimentKey] = variantID
            guard !exposedThisSession.contains(experimentKey) else { return false }
            exposedThisSession.insert(experimentKey)
            return true
        }
        guard shouldEmit else { return }

        analytics.track(
            ExperimentEvent.exposure,
            parameters: [
                ExperimentEvent.Param.experimentKey: .string(experimentKey),
                ExperimentEvent.Param.variant: .string(variantID),
                ExperimentEvent.Param.firstExposure: .bool(!priorExposed.contains(experimentKey))
            ]
        )
    }
}
