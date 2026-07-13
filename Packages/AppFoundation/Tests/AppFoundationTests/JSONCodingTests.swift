import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

private struct DatedPayload: Codable, Equatable {
    let publishedAt: Date
}

private struct DatedEndpoint: Endpoint {
    typealias Response = DatedPayload
    var path: String {
        "/dated"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// 05 §1 kural 8: tarihler ISO 8601 / RFC 3339, `ISO8601DateFormatter` (fractional seconds
/// destekli) ile okunur — fractional'lı VE fractional'sız biçimlerin İKİSİ de kabul edilir.
/// `JSONDecoder.iso8601` fractional saniyeyi reddettiği için tek kaynaklı custom strateji
/// (`JSONDecoder.shortSeriesDefault`) kullanılır.
struct JSONCodingTests {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-07-11T09:31:02Z")!

    @Test func fractionalSaniyeliTarihDecodeOlur() throws {
        let data = Data(#"{"publishedAt":"2026-07-11T09:31:02.123Z"}"#.utf8)

        let payload = try JSONDecoder.shortSeriesDefault().decode(DatedPayload.self, from: data)

        #expect(abs(payload.publishedAt.timeIntervalSince(referenceDate) - 0.123) < 0.0005)
    }

    @Test func fractionalsizTarihDeDecodeOlur() throws {
        let data = Data(#"{"publishedAt":"2026-07-11T09:31:02Z"}"#.utf8)

        let payload = try JSONDecoder.shortSeriesDefault().decode(DatedPayload.self, from: data)

        #expect(payload.publishedAt == referenceDate)
    }

    @Test func iso8601OlmayanTarihDecodingErrorFirlatir() {
        let data = Data(#"{"publishedAt":"11.07.2026 09:31"}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder.shortSeriesDefault().decode(DatedPayload.self, from: data)
        }
    }

    @Test func encoderIso8601Uretir() throws {
        let data = try JSONEncoder.shortSeriesDefault().encode(DatedPayload(publishedAt: referenceDate))

        // Encode edilen tarih, decoder tarafından kayıpsız geri okunabilmelidir (round-trip).
        let decoded = try JSONDecoder.shortSeriesDefault().decode(DatedPayload.self, from: data)
        #expect(decoded.publishedAt == referenceDate)
    }

    @Test func mockAPIClientAyniTarihKonfigurasyonunuKullanir() async throws {
        // Tek kaynaklı konfigürasyon: TestSupport'taki MockAPIClient da fractional tarihi kabul eder.
        let mock = MockAPIClient()
        mock.stub("/dated", with: .success(Data(#"{"publishedAt":"2026-07-11T09:31:02.123Z"}"#.utf8)))

        let response = try await mock.send(DatedEndpoint())

        #expect(abs(response.publishedAt.timeIntervalSince(referenceDate) - 0.123) < 0.0005)
    }
}

extension URLProtocolStubSerialTests {
    /// Canlı `APIClient` yanıt decode'u aynı tarih stratejisini kullanır (regresyon:
    /// fractional tarih tüm yanıtı `AppError.network(.decoding)` ile düşürüyordu).
    struct APIClientDateDecodingTests {
        private let client: APIClient

        init() {
            URLProtocolStub.reset()
            client = APIClient(
                configuration: APIConfiguration(
                    environment: .development,
                    baseURL: URL(string: "https://api.test.local/v1")!
                ),
                urlSession: URLProtocolStub.makeSession()
            )
        }

        @Test func canliIstemciFractionalSaniyeliTarihiDecodeEder() async throws {
            URLProtocolStub.setHandler { request in
                (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"publishedAt":"2026-07-11T09:31:02.123Z"}"#.utf8)
                )
            }

            let response = try await client.send(DatedEndpoint())

            let reference = try #require(ISO8601DateFormatter().date(from: "2026-07-11T09:31:02Z"))
            #expect(abs(response.publishedAt.timeIntervalSince(reference) - 0.123) < 0.0005)
        }
    }
}
