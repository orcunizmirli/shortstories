import Foundation

/// App kompozisyonu için çok tüketicili, current-value (BehaviorSubject) yayın yardımcısı. WalletKit/
/// ProfileKit'in modül-içi `AsyncMulticast`'i public olmadığından (R1: App onları import eder ama
/// internal tipleri göremez) kompozisyon kökünün ÜRETTİĞİ akışlar (ör. `TaskProgressReading`) için
/// App-yerel eşdeğeri gerekir. Semantik `AsyncMulticast` ile birebir: son değer saklanır, geç abone
/// kayıt anında onunla tohumlanır (replay), akış iptalinde abonelik otomatik temizlenir.
///
/// Concurrency: durum `NSLock` ile korunur; `AsyncStream.Continuation` Sendable olduğundan kilit
/// dışında güvenle yield edilir.
final class AsyncBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element?

    init(_ initial: Element? = nil) {
        latest = initial
    }

    /// Anlık son değer (senkron okuma; henüz hiç `send` olmadıysa `nil`).
    var current: Element? {
        lock.withLock { latest }
    }

    /// Yeni abone akışı; kayıt anında (varsa) son değeri replay eder.
    func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            let seed: Element? = lock.withLock {
                continuations[id] = continuation
                return latest
            }
            if let seed {
                continuation.yield(seed)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Öğeyi tüm aktif abonelere iletir (kilit dışında) ve son-değer olarak saklar.
    func send(_ element: Element) {
        let active = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            latest = element
            return Array(continuations.values)
        }
        for continuation in active {
            continuation.yield(element)
        }
    }
}

extension AsyncStream where Element: Sendable {
    /// Bir upstream `AsyncStream`'i saf, Sendable `transform` ile dönüştürür (adaptör map köprüsü):
    /// upstream'in her değeri map edilip yeni akışa yield edilir; downstream iptal edilince upstream
    /// tüketen görev iptal olur. WalletKit `CoinBalance` → `Int`/`WalletSummary` gibi port dönüşümleri
    /// bunu kullanır.
    static func mapping<Upstream: Sendable>(
        _ upstream: AsyncStream<Upstream>,
        _ transform: @escaping @Sendable (Upstream) -> Element
    ) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                for await value in upstream {
                    continuation.yield(transform(value))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
