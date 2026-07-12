/// Paylaşılan içerik ID tipleri (03 §4 R3): `WalletKit`/`RewardsKit`/`ProfileKit` içerik
/// modeline ihtiyaç duyduğunda `ContentKit`'i çekmek yerine bu tipleri kullanır.
/// `HomeRoute` ve `UnlockRequest` de bunları taşır (03 §3.2). Series/Episode modellerinin
/// kendisi `ContentKit`'te yaşar (F1, SS-030).
public struct SeriesID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EpisodeID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
