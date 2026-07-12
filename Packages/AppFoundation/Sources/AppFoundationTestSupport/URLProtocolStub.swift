import Foundation

/// `URLSession`'ı ağa çıkmadan test etmek için `URLProtocol` stub'ı — `APIClient`
/// testlerinin temeli (SS-020'nin çekirdeği).
///
/// DİKKAT: Durum statiktir (URLProtocol sınıf üzerinden örneklenir). Swift Testing
/// testleri paralel koştuğu için bu stub'ı kullanan suite'ler `.serialized`
/// işaretlenmeli ve her test `reset()` ile başlamalıdır.
public final class URLProtocolStub: URLProtocol {
    public typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    // MARK: - Test API

    public static func setHandler(_ newHandler: Handler?) {
        lock.withLock { handler = newHandler }
    }

    /// Alınan istekler, geliş sırasıyla (spy).
    public static var receivedRequests: [URLRequest] {
        lock.withLock { requests }
    }

    public static func reset() {
        lock.withLock {
            handler = nil
            requests = []
        }
    }

    /// Tüm istekleri bu stub'a yönlendiren ephemeral `URLSession` üretir.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    /// Kolaylık: verilen istek için `HTTPURLResponse` üretir.
    public static func httpResponse(for request: URLRequest,
                                    status: Int,
                                    headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(string: "https://invalid.test")!,
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: headers)!
    }

    /// URLProtocol içinde `httpBody` nil gelir; gövdeyi `httpBodyStream`'den okur.
    public static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }
        return data
    }

    // MARK: - URLProtocol

    override public class func canInit(with request: URLRequest) -> Bool { true }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let currentHandler = Self.lock.withLock { () -> Handler? in
            Self.requests.append(request)
            return Self.handler
        }
        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override public func stopLoading() {}
}
