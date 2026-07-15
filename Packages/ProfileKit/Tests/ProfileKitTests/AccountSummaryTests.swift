import AppFoundation
import Testing
@testable import ProfileKit

@Suite("SS-130 hesap özeti türetimi (saf)")
struct AccountSummaryTests {
    @Test func guestAndUnauthenticatedAreGuest() {
        #expect(AccountSummary.make(from: .guest(userID: "g1")).isGuest)
        #expect(AccountSummary.make(from: .unauthenticated).isGuest)
    }

    @Test func linkedCarriesProvider() {
        let summary = AccountSummary.make(from: .linked(userID: "u1", provider: .apple))
        #expect(summary.isLinked)
        #expect(summary.provider == .apple)
        #expect(summary.isGuest == false)
    }

    @Test func loggedOutIsSessionExpired() {
        let summary = AccountSummary.make(from: .loggedOut(previousUserID: "u1", provider: .google))
        #expect(summary.kind == .sessionExpired(provider: .google))
        #expect(summary.isGuest == false)
        #expect(summary.isLinked == false)
        #expect(summary.provider == .google)
    }

    @Test func providerDisplayNames() {
        #expect(AuthProvider.apple.profileDisplayName == "Apple")
        #expect(AuthProvider.google.profileDisplayName == "Google")
        #expect(AuthProvider.email.profileDisplayName == "E-posta")
    }
}
