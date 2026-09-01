import Foundation

/// Deterministik sıralı Idempotency-Key fabrikası (key-1, key-2, …) — UnlockSheet key reuse/yeni-key
/// davranışını doğrulamak için (ağ-retry AYNI key, yeni-intent YENİ key).
final class SequentialKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = 0
    private(set) var generated: [String] = []

    var factory: @Sendable () -> String {
        { [self] in
            lock.withLock {
                counter += 1
                let key = "key-\(counter)"
                generated.append(key)
                return key
            }
        }
    }
}
