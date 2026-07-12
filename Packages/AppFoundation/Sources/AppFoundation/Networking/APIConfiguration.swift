import Foundation

/// Ortam bazlı API konfigürasyonu (SS-006 tohumu — xcconfig entegrasyonu ayrı PR).
/// `baseURL` versiyon önekinin (`/v1`) SAHİBİDİR; endpoint path'leri önek içermez (03 §8.1).
public struct APIConfiguration: Sendable, Equatable {
    public enum Environment: String, Sendable, Equatable, CaseIterable {
        case development
        case staging
        case production
    }

    public let environment: Environment
    public let baseURL: URL

    public init(environment: Environment, baseURL: URL) {
        self.environment = environment
        self.baseURL = baseURL
    }

    public static let development = APIConfiguration(
        environment: .development,
        baseURL: URL(string: "https://api.dev.shortseries.app/v1")!
    )

    public static let staging = APIConfiguration(
        environment: .staging,
        baseURL: URL(string: "https://api.staging.shortseries.app/v1")!
    )

    public static let production = APIConfiguration(
        environment: .production,
        baseURL: URL(string: "https://api.shortseries.app/v1")!
    )
}
