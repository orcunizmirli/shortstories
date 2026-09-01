import Foundation

/// Cihaz-içi, ağsız olay kaydı.
///
/// KANON §1 gereği hiçbir olay cihazdan **otomatik** çıkmaz. Kayıtlar sabit boyutlu bir halka
/// tamponda tutulur; yalnızca kullanıcı Ayarlar'dan dışa aktarırsa dosyaya yazılır.
/// Amaç ürün telemetrisi değil, kullanıcının kendi kurulumunda sorun teşhisidir.
public struct AnalyticsEvent: Sendable, Equatable {
    public let name: String
    public let timestamp: Date
    /// Yalnız düşük kardinaliteli, hassas olmayan alanlar. Serbest metin **yasaktır**.
    public let properties: [String: String]

    public init(name: String, timestamp: Date, properties: [String: String] = [:]) {
        self.name = name
        self.timestamp = timestamp
        self.properties = properties
    }
}

public actor AnalyticsRecorder {
    private let capacity: Int
    private let dateProvider: any DateProviding
    private var buffer: [AnalyticsEvent] = []

    public init(capacity: Int = 500, dateProvider: any DateProviding = SystemDateProvider()) {
        self.capacity = max(1, capacity)
        self.dateProvider = dateProvider
        buffer.reserveCapacity(self.capacity)
    }

    public func record(_ name: String, _ properties: [String: String] = [:]) {
        buffer.append(
            AnalyticsEvent(name: name, timestamp: dateProvider.now, properties: properties)
        )
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    /// Kullanıcının dışa aktarması için anlık kopya.
    public func snapshot() -> [AnalyticsEvent] {
        buffer
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
