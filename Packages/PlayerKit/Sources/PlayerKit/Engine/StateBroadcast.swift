import Foundation

/// Çok aboneli, son değeri replay eden yayın yardımcısı. Combine kanon gereği yasak
/// (03 §7); AsyncStream tek tüketicili olduğundan durum akışı bu sınıfla çoğaltılır.
final class StateBroadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element

    init(initial: Element) {
        latest = initial
    }

    var current: Element {
        lock.withLock { latest }
    }

    /// Yeni abone akışı: ilk değer olarak son bilinen durum replay edilir.
    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            let replay: Element = lock.withLock {
                continuations[id] = continuation
                return latest
            }
            continuation.yield(replay)
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
