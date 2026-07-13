import Foundation

/// Tür (05 §2.3). Kesfet tür filtreleri `id` ile sorgular; `name` lokalize gelir.
public struct Genre: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Onboarding tür tercihi kartları.
    public let iconURL: URL?

    public init(id: String, name: String, iconURL: URL?) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
    }
}

/// Etiket (05 §2.3). DiziDetay etiket rozetleri; Arama'da filtre.
public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
