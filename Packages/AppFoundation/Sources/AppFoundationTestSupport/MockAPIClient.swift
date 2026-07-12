import Foundation
import AppFoundation

/// §5.3 kalıbı: programlanabilir stub cevap + spy kayıt. Cevaplar `path` ile anahtarlanır.
public final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, AppError>] = [:]
    private var received: [any Endpoint] = []
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    // MARK: - Stub

    public var stubbedResponses: [String: Result<Data, AppError>] {
        get { lock.withLock { responses } }
        set { lock.withLock { responses = newValue } }
    }

    public func stub(_ path: String, with result: Result<Data, AppError>) {
        lock.withLock { responses[path] = result }
    }

    public func stub<R: Encodable>(_ path: String, returning value: R) throws {
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
        lock.withLock { received.map { $0.path } }
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
        case .success(let data):
            do {
                return try decoder.decode(E.Response.self, from: data)
            } catch {
                throw AppError.network(.decoding)
            }
        case .failure(let error):
            throw error
        }
    }
}
