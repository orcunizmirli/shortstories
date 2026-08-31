import Foundation

/// Çok tüketicili yayın (multicast) yardımcı tipi: tek bir olay akışını birden çok
/// `AsyncStream` abonesine dağıtır. `WalletStore` entitlement ve bakiye değişimlerini
/// (SS-097; ≤5 sn hedefi push tabanlı olduğundan anında) bununla yayınlar.
///
/// Concurrency: durum `NSLock` ile korunur. Abone SEED'i kayıtla AYNI kilit altında yield edilir
/// (aksi halde eşzamanlı `send()` araya girip aboneyi [V_yeni, V_eski] sırasıyla besler → bayat kalır);
/// `send()` yayınları aktör-serialize olduğundan kilit dışında yield edilir. Combine YOK (kanon §2).
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

    /// YALNIZ TEST: registration ile (kilit BIRAKILDIKTAN sonra) devam kodu arasındaki pencereyi deterministik
    /// kılan enjekte edilebilir askı; `subscribe()` kaydı biter bitmez bir kez çağrılır. Prod'da her zaman `nil`.
    /// Seed-replay atomikliği bununla flake-siz test edilir (ProfileKit `AsyncMulticast` ile aynı seam).
    var onRegisteredForTesting: (@Sendable () -> Void)?

    init() {}

    /// Yeni bir abone akışı verir; kayıt anında (varsa) SON değeri replay eder. Akış iptal edilince
    /// (task iptali / stream bırakılınca) abonelik otomatik temizlenir.
    func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            let hook = lock.withLock { () -> (@Sendable () -> Void)? in
                continuations[id] = continuation
                // Seed'i KAYITLA AYNI kilit altında yield et: eşzamanlı `send()` kayıt ile seed-yield arasına
                // girip aboneyi [V_yeni, V_eski] sırasıyla besleyemez (geç abone V_eski'de bayat kalırdı).
                // `yield` yalnız buffer'a ekler — bloklamaz, senkron termination tetiklemez → kilit altında güvenli.
                if let latest {
                    continuation.yield(latest)
                }
                return onRegisteredForTesting
            }
            hook?() // yalnız test: kayıt-sonrası pencerede send enjekte et (prod'da nil)
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
