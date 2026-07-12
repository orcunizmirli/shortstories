import AppFoundation
import Foundation

public final class MockAnalytics: AnalyticsTracking, @unchecked Sendable {
    public struct Event: Sendable, Equatable {
        public let name: String
        public let parameters: [String: AnalyticsValue]

        public init(name: String, parameters: [String: AnalyticsValue]) {
            self.name = name
            self.parameters = parameters
        }
    }

    private let lock = NSLock()
    private var tracked: [Event] = []

    public init() {}

    public var events: [Event] {
        lock.withLock { tracked }
    }

    public var eventNames: [String] {
        events.map(\.name)
    }

    public func track(_ name: String, parameters: [String: AnalyticsValue]) {
        lock.withLock { tracked.append(Event(name: name, parameters: parameters)) }
    }
}
