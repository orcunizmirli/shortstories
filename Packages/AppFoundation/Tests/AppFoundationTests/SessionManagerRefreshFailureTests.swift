import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// `handleRefreshFailure` sertleştirmesi (self-review, audit MEDIUM): refresh zinciri koptuğunda GEÇİCİ
/// keychain hatası (keychainUnavailable) YIKICI fallback'e (token+snapshot silme, guest'e düşürme)
/// yol açmamalı — yalnız GENUINE yokluk fallback'e gider (05 §4.2 "linked sessizce guest olmaz").
@MainActor
@Suite("SessionManager refresh-failure sertleştirme")
struct SessionManagerRefreshFailureTests {
    @Test func gecicSnapshotGlitchindeLinkedKullaniciGuestaDusurulmez() async throws {
        // handleRefreshFailure state `.linked` DEĞİLKEN snapshot'ı `try?` ile okuyordu → GEÇİCİ glitch nil'e
        // dönüp YIKICI guest-fallback'e (token+snapshot SİLME) sokuyordu → gerçekte LINKED kullanıcı SESSİZCE
        // guest olur. Fix: geçici hatada nil dön, HİÇBİR ŞEY silme. Backing'de linked snapshot; state .unauthenticated.
        let store = ReadFailingSecureStore(failReadFor: .sessionSnapshot)
        try store.backing.setString("at_linked", forKey: .accessToken)
        try store.backing.setString("rt_linked", forKey: .refreshToken)
        let linked = StoredSessionSnapshot(userID: "usr_linked", provider: .google)
        try store.backing.setData(JSONEncoder().encode(linked), forKey: .sessionSnapshot)
        let mgr = SessionManager(
            apiClient: MockAPIClient(),
            secureStore: store,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )
        store.arm() // bundan sonra .sessionSnapshot OKUMASI geçici kopar

        let token = await mgr.handleRefreshFailure()

        #expect(token == nil) // kurtaramadı ama YIKMADI
        // Linked snapshot + tokenlar KORUNDU (silinmedi) → linked kullanıcı guest'e düşmez.
        let snapData = try #require(try store.backing.data(forKey: .sessionSnapshot))
        #expect(try JSONDecoder().decode(StoredSessionSnapshot.self, from: snapData) == linked)
        #expect(try store.backing.string(forKey: .refreshToken) == "rt_linked")
        #expect(try store.backing.string(forKey: .accessToken) == "at_linked")
        #expect(mgr.state == .unauthenticated) // guest'e bootstrap edilmedi
    }
}
