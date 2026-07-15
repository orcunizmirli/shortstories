import Foundation

/// Çok tüketicili yayın (multicast): tek olay akışını birden çok `AsyncStream` abonesine
/// dağıtır. SS-161'de dil tercihi değişimleri (uygulama + altyazı) bununla ANINDA yayınlanır;
/// altyazı dilini PlayerKit (SS-046) `SubtitleLanguageProviding` üzerinden bu akışla okur.
///
/// Concurrency: durum `NSLock` ile korunur; `AsyncStream.Continuation` Sendable olduğundan
/// kilit dışında güvenle yield edilir. Combine YOK (kanon §2). WalletKit'teki `AsyncMulticast`
/// ile aynı sözleşme — R2 gereği kopyalanır (ProfileKit WalletKit'i import edemez).
///
/// Current-value (BehaviorSubject) semantiği: SON yayınlanan değer saklanır ve yeni abone kayıt
/// anında onunla tohumlanır — böylece geç abone (Ayarlar'dan set ile Player'ın subscribe'ı
/// arasındaki pencere) mevcut tercihi kaçırmaz.
final class AsyncMulticast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element?

    /// YALNIZ TEST: registration ile (post-lock) devam kodu arasındaki pencereyi deterministik
    /// kılan enjekte edilebilir askı; `subscribe()` kaydı biter bitmez (kilit BIRAKILDIKTAN sonra)
    /// bir kez çağrılır. Prod'da her zaman `nil`. Seed replay atomikliği bununla test edilir.
    var onRegisteredForTesting: (@Sendable () -> Void)?

    init() {}

    /// Yeni abone akışı; kayıt anında (varsa) SON değeri replay eder. Akış iptal edilince
    /// abonelik otomatik temizlenir.
    ///
    /// Atomiklik: continuation kaydı + current-value seed yield'i AYNI kritik bölümde (kilit
    /// içinde) yapılır — böylece eşzamanlı `send()` seed'den ASLA önce teslim edemez; geç abone
    /// her zaman en-yeni değeri SON görür (last-write-wins tüketici bayatta kalmaz).
    func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            let hook = lock.withLock { () -> (@Sendable () -> Void)? in
                continuations[id] = continuation
                if let latest {
                    continuation.yield(latest)
                }
                return onRegisteredForTesting
            }
            hook?()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Öğeyi tüm aktif abonelere iletir (kilit dışında yield) ve son-değer olarak saklar.
    func send(_ element: Element) {
        let active = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            latest = element
            return Array(continuations.values)
        }
        for continuation in active {
            continuation.yield(element)
        }
    }

    /// Tüm abonelikleri sonlandırır (teardown).
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
