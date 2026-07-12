import Foundation
import Testing
@testable import AppFoundation

private func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

struct RetryPolicyTests {
    private let retryableError = AppError.network(.server(status: 500))

    @Test func varsayilanPolitikaBackoffTablosunuUygular() throws {
        // Nominal 0.5 / 1 / 2 sn; jitter çarpanı 0.8...1.2 (03 §8.3).
        let policy = RetryPolicy.default

        let delay0 = try #require(policy.delay(afterAttempt: 0, error: retryableError))
        #expect(seconds(delay0) >= 0.4 && seconds(delay0) <= 0.6)

        let delay1 = try #require(policy.delay(afterAttempt: 1, error: retryableError))
        #expect(seconds(delay1) >= 0.8 && seconds(delay1) <= 1.2)

        let delay2 = try #require(policy.delay(afterAttempt: 2, error: retryableError))
        #expect(seconds(delay2) >= 1.6 && seconds(delay2) <= 2.4)
    }

    @Test func retryHakkiBitinceNilDoner() {
        #expect(RetryPolicy.default.delay(afterAttempt: 3, error: retryableError) == nil)
        #expect(RetryPolicy.default.delay(afterAttempt: 10, error: retryableError) == nil)
    }

    @Test func neverPolitikasiHicRetryVermez() {
        #expect(RetryPolicy.never.delay(afterAttempt: 0, error: retryableError) == nil)
    }

    @Test func retryableOlmayanHatadaNilDoner() {
        let policy = RetryPolicy.default
        #expect(policy.delay(afterAttempt: 0, error: .network(.server(status: 404))) == nil)
        #expect(policy.delay(afterAttempt: 0, error: .network(.decoding)) == nil)
        #expect(policy.delay(afterAttempt: 0, error: .auth(.sessionExpired)) == nil)
        #expect(policy.delay(afterAttempt: 0, error: .wallet(.insufficientCoins)) == nil)
    }

    @Test func negatifAttemptNilDoner() {
        #expect(RetryPolicy.default.delay(afterAttempt: -1, error: retryableError) == nil)
    }

    @Test func ozelPolitikaParametreleriUygulanir() throws {
        let policy = RetryPolicy(maxRetries: 1,
                                 baseDelay: .milliseconds(10),
                                 multiplier: 3,
                                 jitter: 1.0...1.0)
        let delay0 = try #require(policy.delay(afterAttempt: 0, error: retryableError))
        #expect(abs(seconds(delay0) - 0.010) < 0.0001)
        #expect(policy.delay(afterAttempt: 1, error: retryableError) == nil)
    }
}
