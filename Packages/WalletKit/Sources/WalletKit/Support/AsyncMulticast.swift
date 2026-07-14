import Foundation

/// Çok tüketicili yayın (multicast) yardımcı tipi: tek bir olay akışını birden çok
/// `AsyncStream` abonesine dağıtır. `WalletStore` entitlement ve bakiye değişimlerini
/// (SS-097; ≤5 sn hedefi push tabanlı olduğundan anında) bununla yayınlar.
///
/// Concurrency: durum `NSLock` ile korunur; `AsyncStream.Continuation` Sendable olduğundan
/// kilit dışında güvenle yield edilir. Combine YOK (kanon §2).
///
/// Current-value (BehaviorSubject) semantiği: SON yayınlanan değer saklanır ve yeni abone
/// KAYIT ANINDA onunla tohumlanır. Bakiye/entitlement "mevcut durum" akışlarıdır — tüketici
/// `currentBalance()` ile subscribe arasındaki pencerede kaçan bir `send`'i bu replay ile telafi
/// eder; aksi halde UI kalıcı bayat kalırdı (SS-097).
final class AsyncMulticast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    /// En son yayınlanan değer (geç abonelere replay edilir). Henüz hiç `send` olmadıysa `nil`.
    private var latest: Element?

    init() {}

    /// Yeni bir abone akışı verir; kayıt anında (varsa) SON değeri replay eder. Akış iptal edilince
    /// (task iptali / stream bırakılınca) abonelik otomatik temizlenir.
    func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            let seed: Element? = lock.withLock {
                continuations[id] = continuation
                return latest
            }
            // Kayıt ile atomik: geç abone mevcut değeri kaçırmaz (send-then-subscribe telafisi).
            if let seed {
                continuation.yield(seed)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Öğeyi tüm aktif abonelere iletir (kilit dışında yield edilir) ve son-değer olarak saklar.
    func send(_ element: Element) {
        let active = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            latest = element
            return Array(continuations.values)
        }
        for continuation in active {
            continuation.yield(element)
        }
    }

    /// Tüm abonelikleri sonlandırır (uygulama kapanışı / teardown).
    func finishAll() {
        let active = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in active {
            continuation.finish()
        }
    }
}
