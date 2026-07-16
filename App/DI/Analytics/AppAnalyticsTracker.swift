import AppFoundation

/// `AnalyticsTracking`'in canlı, registry-doğrulamalı kompozisyon-kökü uygulaması (03 §5.1, 08 §2).
/// `LiveDependencies.analytics` artık `NoopAnalyticsTracker` DEĞİL bu tiptir (F1 kapanışı).
///
/// R6 gereği gerçek analitik sink (Firebase/Crashlytics) App katmanında hapsolur; SDK bağlanana
/// kadar (SS-150+) event'ler `Logging`'e yazılır ve isteğe bağlı ikincil sink'lere (`AnalyticsSink`)
/// iletilir — böylece QA/entegrasyon testleri gerçek SDK olmadan emit'i gözlemler. Her event
/// `AnalyticsEventRegistry` ile doğrulanır: kayıtsız/bozuk adlar `fault` loglar ama DÜŞÜRÜLMEZ
/// (analitik kaybı üretimde geri alınamaz — §2.3 doğrulaması non-destructive).
///
/// Concurrency: `AnalyticsTracking.track` nonisolated senkron çağrılır (her feature @MainActor
/// model'inden ateşlenir ama protokol Sendable ve senkron). Bu tip immutable bağımlılıklar taşır ve
/// `Sendable`'dır; sink fan-out kilitsiz (immutable dizi) yürür.
public struct AppAnalyticsTracker: AnalyticsTracking {
    private let logger: any Logging
    private let sinks: [any AnalyticsSink]
    /// Kayıtsız event'te davranış: DEBUG'da precondition ihlali gibi görünür `fault`, RELEASE'te
    /// yalnız log — üretimde asla event düşürülmez/çökmez.
    private let strictInDebug: Bool

    public init(
        logger: any Logging,
        sinks: [any AnalyticsSink] = [],
        strictInDebug: Bool = true
    ) {
        self.logger = logger
        self.sinks = sinks
        self.strictInDebug = strictInDebug
    }

    public func track(_ name: String, parameters: [String: AnalyticsValue]) {
        switch AnalyticsEventRegistry.validate(name) {
        case .valid:
            break
        case .malformed:
            report("analytics: malformed event name '\(name)' (08 §2.1 snake_case ihlali)")
        case .unregistered:
            report("analytics: unregistered event '\(name)' (08 §2.3 — önce registry'e ekle)")
        }
        // Doğrulama ne olursa olsun emit et (non-destructive): registry drift'i telemetriyi kesmez.
        for sink in sinks {
            sink.record(event: name, parameters: parameters)
        }
        logger.debug("analytics ▸ \(name) \(Self.describe(parameters))")
    }

    private func report(_ message: String) {
        logger.fault(message)
        #if DEBUG
            if strictInDebug {
                assertionFailure(message)
            }
        #endif
    }

    /// PII kuralı (03 §10.3): parametre DEĞERLERİ loglanır ama bu yüzey yalnız analitik anahtar/değer
    /// taşır (e-posta/token/receipt analitik parametresi DEĞİLDİR — kaynak taraflarca garanti). Anahtar
    /// sırası deterministik olsun diye sıralanır (test/gözlem kolaylığı).
    static func describe(_ parameters: [String: AnalyticsValue]) -> String {
        guard !parameters.isEmpty else { return "{}" }
        let pairs = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.describe($0.value))" }
        return "{" + pairs.joined(separator: ", ") + "}"
    }

    private static func describe(_ value: AnalyticsValue) -> String {
        switch value {
        case let .string(string): string
        case let .int(int): String(int)
        case let .double(double): String(double)
        case let .bool(bool): String(bool)
        }
    }
}

/// Gerçek analitik hedefi köprüsü (Firebase Analytics vb.) — App kompozisyonunda bağlanır. F1'de sink
/// listesi boştur (yalnız log); SS-150 Firebase SDK'sı geldiğinde `FirebaseAnalyticsSink` bu protokole
/// uyar ve `AppAnalyticsTracker(sinks:)` ile enjekte edilir. SDK R6 gereği bu sink uygulamasında hapsolur.
public protocol AnalyticsSink: Sendable {
    func record(event name: String, parameters: [String: AnalyticsValue])
}
