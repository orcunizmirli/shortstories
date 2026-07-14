import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

private struct Payload: Codable, Equatable {
    let value: String
}

/// Retry'sız uç: eşleme testlerinde hata İLK denemede yüzer.
private struct NoRetryEndpoint: Endpoint {
    typealias Response = Payload
    var path: String {
        "/playback/authorize-benzeri"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// Testten enjekte edilen politikayla retry davranışını inceleyen uç.
private struct RetryingEndpoint: Endpoint {
    typealias Response = Payload
    var retry: RetryPolicy
    var path: String {
        "/feed"
    }

    var method: HTTPMethod {
        .get
    }

    var retryPolicy: RetryPolicy {
        retry
    }
}

/// HTTP statü + `error.code` → tipli `AppError` eşlemesi YALNIZ burada, AppFoundation API
/// katmanında yapılır (05 §10.3 sınır kuralı); feature'lar ham HTTP kodunu görmez.
extension URLProtocolStubSerialTests {
    struct APIClientErrorMappingTests {
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

        // MARK: - 403 EPISODE_LOCKED (05 §10.2 satırı; details şeması 05 §4.4)

        @Test func episodeLockedDetailsYukuyleTiplenmisHatayaEslenir() async {
            // 05 §4.4 fixture'ı: UnlockSheet'in TEK istekle açılması bu yüke dayanır.
            let fixture = Data("""
            {"error":{"code":"EPISODE_LOCKED","message":"Bu bölüm kilitli.","details":\
            {"unlockPrice":60,"adUnlockEligible":true,"wallet":{"purchasedCoins":20,"earnedCoins":15}}},\
            "requestId":"req_01HZY"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 403), fixture)
            }

            let expected = AppError.content(.episodeLocked(EpisodeLockDetails(
                unlockPrice: 60,
                adUnlockEligible: true,
                wallet: EpisodeLockDetails.WalletSnapshot(purchasedCoins: 20, earnedCoins: 15)
            )))
            await #expect(throws: expected) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func coinYoluKapaliKilitNilFiyatlaEslenir() async {
            // 05 §2.2 genişleme noktası: `unlockPrice: null` = coin yolu kapalı kilit.
            let fixture = Data("""
            {"error":{"code":"EPISODE_LOCKED","message":"Bu bölüm kilitli.","details":\
            {"unlockPrice":null,"adUnlockEligible":true}},"requestId":"req_01HZY"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 403), fixture)
            }

            let expected = AppError.content(.episodeLocked(EpisodeLockDetails(
                unlockPrice: nil,
                adUnlockEligible: true,
                wallet: nil
            )))
            await #expect(throws: expected) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func episodeLockedDetailsYoksaGenelServerHatasinaDusulur() async {
            // details olmadan UnlockSheet tek istekle açılamaz; HTTP sınıfının varsayılanına dönülür.
            let fixture = Data(#"{"error":{"code":"EPISODE_LOCKED","message":"Bu bölüm kilitli."}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 403), fixture)
            }

            await #expect(throws: AppError.network(.server(status: 403))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func forbiddenKodluDortYuzUcGenelServerHatasiKalir() async {
            let fixture = Data(#"{"error":{"code":"FORBIDDEN","message":"Yetkin yok."}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 403), fixture)
            }

            await #expect(throws: AppError.network(.server(status: 403))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        // MARK: - Cüzdan/IAP kod zenginleştirmesi (05 §4.5/4.6/10.2: details tipli çıkarım)

        @Test func insufficientCoinsShortfallDetailindenCikar() async {
            // 402 INSUFFICIENT_COINS gövdesinden shortfall çıkarılır → tipli WalletError.
            let fixture = Data("""
            {"error":{"code":"INSUFFICIENT_COINS","message":"Yetersiz coin.",\
            "details":{"shortfall":30}},"requestId":"req_01J0"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 402), fixture)
            }

            await #expect(throws: AppError.wallet(.insufficientCoins(shortfall: 30))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func priceChangedCurrentPriceDetailindenCikar() async {
            // 409 PRICE_CHANGED gövdesinden currentPrice çıkarılır → tipli WalletError.
            let fixture = Data("""
            {"error":{"code":"PRICE_CHANGED","message":"Fiyat değişti.",\
            "details":{"currentPrice":75}},"requestId":"req_01J1"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 409), fixture)
            }

            await #expect(throws: AppError.wallet(.priceChanged(currentPrice: 75))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func receiptAlreadyProcessedOriginalDetailindenCikar() async {
            // 409 RECEIPT_ALREADY_PROCESSED gövdesinden original çıkarılır → tipli WalletError.
            let fixture = Data("""
            {"error":{"code":"RECEIPT_ALREADY_PROCESSED","message":"Zaten işlendi.",\
            "details":{"original":"txn_original_9001"}},"requestId":"req_01J2"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 409), fixture)
            }

            await #expect(throws: AppError.wallet(.receiptAlreadyProcessed(originalTransactionID: "txn_original_9001"))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func receiptInvalidDortYuzYirmiIkiTipliEslenir() async {
            let fixture = Data(#"{"error":{"code":"RECEIPT_INVALID","message":"Geçersiz."}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 422), fixture)
            }

            await #expect(throws: AppError.wallet(.receiptInvalid)) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func detailsizInsufficientCoinsNilShortfallIleEslenir() async {
            // Gövde `details` taşımıyorsa shortfall nil kalır (kod yine tanınır).
            let fixture = Data(#"{"error":{"code":"INSUFFICIENT_COINS","message":"Yetersiz."}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 402), fixture)
            }

            await #expect(throws: AppError.wallet(.insufficientCoins(shortfall: nil))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func taninmayanKodluDortYuzIkiGenelServerHatasiKalir() async {
            // Kod tanınmıyorsa HTTP sınıfının varsayılanı korunur (geriye-uyum).
            let fixture = Data(#"{"error":{"code":"SOME_OTHER","message":"?"}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 402), fixture)
            }

            await #expect(throws: AppError.network(.server(status: 402))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        // MARK: - 410 SIGNED_URL_EXPIRED (05 §10.2 satırı)

        @Test func signedURLExpiredPlaybackHatasinaEslenir() async {
            let fixture = Data("""
            {"error":{"code":"SIGNED_URL_EXPIRED","message":"Oynatma bağlantısının süresi doldu.",\
            "retryable":true},"requestId":"req_01HZZ"}
            """.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 410), fixture)
            }

            await #expect(throws: AppError.playback(.signedURLExpired)) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        @Test func bilinmeyenKodluDortYuzOnGenelServerHatasiKalir() async {
            let fixture = Data(#"{"error":{"code":"TANINMAYAN_KOD","message":"?"}}"#.utf8)
            URLProtocolStub.setHandler { request in
                (URLProtocolStub.httpResponse(for: request, status: 410), fixture)
            }

            await #expect(throws: AppError.network(.server(status: 410))) {
                _ = try await client.send(NoRetryEndpoint())
            }
        }

        // MARK: - 429 Retry-After (05 §10.2: "Retry-After header'ına uy")

        @Test func retryAfterHeaderiBackoffYerineKullanilir() async throws {
            // Politika 5 sn'lik backoff derdi; header 0 sn der. Header'a uyulmazsa test bariz yavaşlar.
            let endpoint = RetryingEndpoint(retry: RetryPolicy(maxRetries: 1, baseDelay: .seconds(5)))
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 2 {
                    return (
                        URLProtocolStub.httpResponse(for: request, status: 429, headers: ["Retry-After": "0"]),
                        Data()
                    )
                }
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let clock = ContinuousClock()
            let start = clock.now
            let response = try await client.send(endpoint)
            let elapsed = clock.now - start

            #expect(response == Payload(value: "ok"))
            #expect(URLProtocolStub.receivedRequests.count == 2)
            #expect(elapsed < .seconds(2))
        }

        @Test func retryHakkiYoksaRetryAfterliDortYuzYirmiDokuzServerHatasiOlarakYuzer() async {
            URLProtocolStub.setHandler { request in
                (
                    URLProtocolStub.httpResponse(for: request, status: 429, headers: ["Retry-After": "0"]),
                    Data()
                )
            }

            await #expect(throws: AppError.network(.server(status: 429))) {
                _ = try await client.send(NoRetryEndpoint())
            }
            #expect(URLProtocolStub.receivedRequests.count == 1)
        }

        @Test func headersizDortYuzYirmiDokuzBackoffIleRetryAlir() async throws {
            let endpoint = RetryingEndpoint(retry: RetryPolicy(maxRetries: 1, baseDelay: .milliseconds(1)))
            URLProtocolStub.setHandler { request in
                if URLProtocolStub.receivedRequests.count < 2 {
                    return (URLProtocolStub.httpResponse(for: request, status: 429), Data())
                }
                return (
                    URLProtocolStub.httpResponse(for: request, status: 200),
                    Data(#"{"value":"ok"}"#.utf8)
                )
            }

            let response = try await client.send(endpoint)

            #expect(response == Payload(value: "ok"))
            #expect(URLProtocolStub.receivedRequests.count == 2)
        }
    }
}

// MARK: - Retry-After header ayrıştırma (ağ gerekmez)

struct RetryAfterHeaderParsingTests {
    @Test func saniyeDegeriParseEdilir() {
        #expect(APIClient.retryAfterDelay(fromHeaderValue: "2") == .seconds(2))
        #expect(APIClient.retryAfterDelay(fromHeaderValue: "0") == .zero)
    }

    @Test func degerUstSinirlaKirpilir() {
        #expect(APIClient.retryAfterDelay(fromHeaderValue: "9999") == APIClient.maxRetryAfterDelay)
        #expect(APIClient.maxRetryAfterDelay == .seconds(30))
    }

    @Test func gecersizVeNegatifDegerNilDoner() {
        #expect(APIClient.retryAfterDelay(fromHeaderValue: nil) == nil)
        #expect(APIClient.retryAfterDelay(fromHeaderValue: "yarin") == nil)
        #expect(APIClient.retryAfterDelay(fromHeaderValue: "-1") == nil)
    }
}
