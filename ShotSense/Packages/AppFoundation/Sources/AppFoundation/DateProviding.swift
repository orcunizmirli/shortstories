import Foundation

/// Testlerde zamanı sabitleyebilmek için saat erişiminin tek noktası.
///
/// `Date()` doğrudan çağrılmaz: kota sıfırlama (aylık), recency skoru ve geri çekilme
/// zamanlaması deterministik test edilebilir olmalıdır.
public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

/// Testler için sabit/ilerletilebilir saat.
public final class MutableDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_767_225_600)) {
        current = now
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}
