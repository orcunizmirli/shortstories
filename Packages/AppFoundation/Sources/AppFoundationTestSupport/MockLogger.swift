import AppFoundation
import Foundation

public final class MockLogger: Logging, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let level: LogLevel
        public let message: String

        public init(level: LogLevel, message: String) {
            self.level = level
            self.message = message
        }
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []

    public init() {}

    public var entries: [Entry] {
        lock.withLock { recorded }
    }

    public func messages(at level: LogLevel) -> [String] {
        entries.filter { $0.level == level }.map(\.message)
    }

    public func log(_ level: LogLevel, _ message: String) {
        lock.withLock { recorded.append(Entry(level: level, message: message)) }
    }
}
