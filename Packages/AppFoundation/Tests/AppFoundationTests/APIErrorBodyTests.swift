import Foundation
import Testing
@testable import AppFoundation

/// 05 §10.1 hata gövdesi şeması: tüm 4xx/5xx yanıtları aynı zarfı kullanır.
struct APIErrorBodyTests {
    @Test func hataZarfiSemayaGoreParseEdilir() throws {
        let data = Data("""
        {"error":{"code":"INSUFFICIENT_COINS","message":"Yetersiz coin.",\
        "details":{"shortfall":25},"retryable":false},"requestId":"req_01HZY"}
        """.utf8)

        let body = try JSONDecoder.shortSeriesDefault().decode(APIErrorBody.self, from: data)

        #expect(body.error.code == "INSUFFICIENT_COINS")
        #expect(body.error.message == "Yetersiz coin.")
        #expect(body.error.retryable == false)
        #expect(body.error.details == .object(["shortfall": .number(25)]))
        #expect(body.requestId == "req_01HZY")
    }

    @Test func opsiyonelAlanlarYokkenDeParseBasarir() throws {
        let data = Data(#"{"error":{"code":"INTERNAL","message":"Bir şeyler ters gitti."}}"#.utf8)

        let body = try JSONDecoder.shortSeriesDefault().decode(APIErrorBody.self, from: data)

        #expect(body.error.code == "INTERNAL")
        #expect(body.error.details == nil)
        #expect(body.error.retryable == nil)
        #expect(body.requestId == nil)
    }

    @Test func icIceDinamikDetailsJSONValueOlarakOkunur() throws {
        let data = Data("""
        {"error":{"code":"EPISODE_LOCKED","message":"Kilitli.","details":\
        {"unlockPrice":null,"adUnlockEligible":true,"tags":["a","b"]}}}
        """.utf8)

        let body = try JSONDecoder.shortSeriesDefault().decode(APIErrorBody.self, from: data)

        #expect(body.error.details == .object([
            "unlockPrice": .null,
            "adUnlockEligible": .bool(true),
            "tags": .array([.string("a"), .string("b")])
        ]))
    }
}
