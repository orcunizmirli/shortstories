import Foundation
import Testing
@testable import AppFoundation

struct AppErrorTests {
    // MARK: - isRetryable (03 §8.3 tablosu)

    @Test func besYuzluTimeoutVeOfflineRetryable() {
        #expect(AppError.network(.server(status: 500)).isRetryable)
        #expect(AppError.network(.server(status: 503)).isRetryable)
        #expect(AppError.network(.server(status: 429)).isRetryable)
        #expect(AppError.network(.timeout).isRetryable)
        #expect(AppError.network(.offline).isRetryable)
    }

    @Test func dortYuzluVeDecodingRetryableDegil() {
        #expect(!AppError.network(.server(status: 400)).isRetryable)
        #expect(!AppError.network(.server(status: 404)).isRetryable)
        #expect(!AppError.network(.decoding).isRetryable)
    }

    @Test func authVeWalletRetryableDegil() {
        #expect(!AppError.auth(.sessionExpired).isRetryable)
        #expect(!AppError.auth(.guestBootstrapFailed).isRetryable)
        #expect(!AppError.wallet(.insufficientCoins(shortfall: nil)).isRetryable)
        #expect(!AppError.wallet(.purchaseFailed(.pending)).isRetryable)
        #expect(!AppError.content(.notFound).isRetryable)
        #expect(!AppError.storage(.diskFull).isRetryable)
        #expect(!AppError.featureDisabled(flag: "x").isRetryable)
        #expect(!AppError.unexpected(underlying: "x").isRetryable)
    }

    @Test func imzaliURLSuresiDolmasiRetryable() {
        #expect(AppError.playback(.signedURLExpired).isRetryable)
        #expect(!AppError.playback(.assetUnavailable).isRetryable)
        #expect(!AppError.playback(.drmDenied).isRetryable)
    }

    // MARK: - userFacingMessage (03 §10.2)

    @Test func kullaniciyaGorunenHatalarMesajTasir() {
        #expect(AppError.network(.offline).userFacingMessage != nil)
        #expect(AppError.network(.timeout).userFacingMessage != nil)
        #expect(AppError.auth(.sessionExpired).userFacingMessage != nil)
        #expect(AppError.wallet(.insufficientCoins(shortfall: 12)).userFacingMessage != nil)
        #expect(AppError.wallet(.receiptValidationFailed).userFacingMessage != nil)
        #expect(AppError.content(.regionBlocked).userFacingMessage != nil)
        #expect(AppError.storage(.diskFull).userFacingMessage != nil)
    }

    @Test func arkaPlanHatalariMesajTasimaz() {
        #expect(AppError.playback(.signedURLExpired).userFacingMessage == nil)
        #expect(AppError.wallet(.purchaseFailed(.userCancelled)).userFacingMessage == nil)
        #expect(AppError.featureDisabled(flag: "x").userFacingMessage == nil)
        #expect(AppError.unexpected(underlying: "x").userFacingMessage == nil)
    }

    // MARK: - Equatable

    @Test func esitlikKarsilastirmasi() {
        #expect(AppError.network(.server(status: 500)) == AppError.network(.server(status: 500)))
        #expect(AppError.network(.server(status: 500)) != AppError.network(.server(status: 502)))
        #expect(AppError.wallet(.purchaseFailed(.pending)) != AppError.wallet(.purchaseFailed(.unknown)))
    }
}
