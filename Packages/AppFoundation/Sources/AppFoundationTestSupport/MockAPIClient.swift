import AppFoundation
import Foundation

/// §5.3 kalıbı: programlanabilir stub cevap + spy kayıt. Cevaplar `path` ile anahtarlanır.
public final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, AppError>] = [:]
    private var received: [any Endpoint] = []
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init() {
        // Canlı APIClient ile AYNI tek kaynaklı kodlama konfigürasyonu (JSONCoding.swift):
        // fractional saniyeli ISO 8601 tarihler mock'ta da kabul edilir.
        decoder = .shortSeriesDefault()
        encoder = .shortSeriesDefault()
    }

    // MARK: - Stub

    public var stubbedResponses: [String: Result<Data, AppError>] {
        get { lock.withLock { responses } }
        set { lock.withLock { responses = newValue } }
    }

    public func stub(_ path: String, with result: Result<Data, AppError>) {
        lock.withLock { responses[path] = result }
    }

    public func stub(_ path: String, returning value: some Encodable) throws {
        let data = try encoder.encode(value)
        lock.withLock { responses[path] = .success(data) }
    }

    public func stub(_ path: String, throwing error: AppError) {
        lock.withLock { responses[path] = .failure(error) }
    }

    // MARK: - Spy

    public var receivedEndpoints: [any Endpoint] {
        lock.withLock { received }
    }

    public var receivedPaths: [String] {
        lock.withLock { received.map(\.path) }
    }

    // MARK: - APIClientProtocol

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let result: Result<Data, AppError>? = lock.withLock {
            received.append(endpoint)
            return responses[endpoint.path]
        }
        guard let result else {
            throw AppError.unexpected(underlying: "MockAPIClient: '\(endpoint.path)' için stub tanımlı değil")
        }
        switch result {
        case let .success(data):
            // Canlı APIClient ile aynı 204/boş-gövde kısa-devresi: boş `Data` stub'ı gövde-taşımayan
            // tip için sahte EOF üretmeden başarı döner (05 §4.2.1/§8).
            if data.isEmpty {
                if let empty = decoder.decodeEmptyBody(as: E.Response.self) {
                    return empty
                }
                throw AppError.network(.decoding)
            }
            do {
                return try decoder.decode(E.Response.self, from: data)
            } catch {
                throw AppError.network(.decoding)
            }
        case let .failure(error):
            throw error
        }
    }
}
