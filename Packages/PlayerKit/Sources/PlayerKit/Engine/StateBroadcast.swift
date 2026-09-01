import Foundation

/// Çok aboneli, son değeri replay eden yayın yardımcısı. Combine kanon gereği yasak
/// (03 §7); AsyncStream tek tüketicili olduğundan durum akışı bu sınıfla çoğaltılır.
final class StateBroadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element

    /// Test kancası (AsyncMulticast simetriği): kayıt tamamlanır tamamlanmaz çağrılır → seed penceresine
    /// araya send sokup stale-seed-last yarışını deterministik kurmaya yarar. Üretimde nil.
    var onRegisteredForTesting: (@Sendable () -> Void)?

    init(initial: Element) {
        latest = initial
    }

    var current: Element {
        lock.withLock { latest }
    }

    /// Yeni abone akışı: ilk değer olarak son bilinen durum replay edilir. Seed'i KİLİT ALTINDA yield eder
    /// (AsyncMulticast/SessionBroadcaster simetriği): kayıt ile seed-yield arasında send() araya girip aboneyi
    /// [yeni, bayat-seed] sırasıyla besleyemesin → abonenin SON gördüğü değer daima en-yeni kalır (stale-seed-last önlemi).
    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
                continuation.yield(latest)
            }
            onRegisteredForTesting?()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = lock.withLock { continuations.removeValue(forKey: id) }
            }
        }
    }

    func send(_ value: Element) {
        let targets: [AsyncStream<Element>.Continuation] = lock.withLock {
            latest = value
            return Array(continuations.values)
        }
        for continuation in targets {
            continuation.yield(value)
        }
    }

    func finish() {
        let targets: [AsyncStream<Element>.Continuation] = lock.withLock {
            defer { continuations.removeAll() }
            return Array(continuations.values)
        }
        for continuation in targets {
            continuation.finish()
        }
    }
}
