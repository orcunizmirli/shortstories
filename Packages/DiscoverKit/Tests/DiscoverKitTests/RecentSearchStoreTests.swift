import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import DiscoverKit

@Suite("PreferencesRecentSearchStore")
struct RecentSearchStoreTests {
    @Test func addMostRecentFirstWithDedup() {
        let store = PreferencesRecentSearchStore(preferences: MockPreferences())
        store.add("ceo")
        store.add("revenge")
        store.add("ceo") // tekrar → başa taşınır, çift olmaz
        #expect(store.load() == ["ceo", "revenge"])
    }

    @Test func capsAtTen() {
        let store = PreferencesRecentSearchStore(preferences: MockPreferences())
        for index in 0 ..< 15 {
            store.add("query\(index)")
        }
        #expect(store.load().count == maxRecentSearches)
        #expect(store.load().first == "query14")
    }

    @Test func normalizesBeforeStoring() {
        let store = PreferencesRecentSearchStore(preferences: MockPreferences())
        store.add("  midnight  ")
        #expect(store.load() == ["midnight"])
        // Boş sorgu saklanmaz.
        store.add("   ")
        #expect(store.load() == ["midnight"])
    }

    @Test func removeAndClear() {
        let store = PreferencesRecentSearchStore(preferences: MockPreferences())
        store.add("ceo")
        store.add("revenge")
        store.remove("ceo")
        #expect(store.load() == ["revenge"])
        store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func persistsAcrossStoreInstances() {
        let preferences = MockPreferences()
        PreferencesRecentSearchStore(preferences: preferences).add("ceo romance")
        // Aynı preferences ile yeni store örneği aynı veriyi görür.
        let reopened = PreferencesRecentSearchStore(preferences: preferences)
        #expect(reopened.load() == ["ceo romance"])
    }
}
