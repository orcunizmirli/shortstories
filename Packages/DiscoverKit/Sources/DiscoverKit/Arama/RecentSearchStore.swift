import AppFoundation
import Foundation

/// Cihaz-yerel son aramalar defteri (02 §4.11 edge case: en çok 10, hesaba senkronlanmaz —
/// Faz 1). Sıra: en yeni önce; tekrar aranan sorgu başa taşınır (dedup).
public protocol RecentSearchStoring: Sendable {
    func load() -> [String]
    /// Sorguyu başa ekler (varsa yukarı taşır), listeyi `maxRecentSearches`e kırpar.
    func add(_ query: String)
    func remove(_ query: String)
    func clear()
}

/// Maksimum saklanan son arama sayısı (02 §4.11 / 01 `DSC-03`).
public let maxRecentSearches = 10

/// `PreferencesStoring` (UserDefaults) tabanlı uygulama. Liste tek `String` değerinde
/// satırbaşıyla ayrılmış saklanır; sorgular `normalize` ile satırbaşından arındırıldığından
/// ayraç çakışması olmaz. Cihaz-yerel; token/gizli veri değil → PreferencesStoring uygun.
public struct PreferencesRecentSearchStore: RecentSearchStoring {
    static let key = PreferenceKey(name: "discover.recent_searches", default: "")

    private let preferences: any PreferencesStoring

    public init(preferences: any PreferencesStoring) {
        self.preferences = preferences
    }

    public func load() -> [String] {
        let raw = preferences.value(for: Self.key)
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    public func add(_ query: String) {
        let normalized = SearchInputMachine.normalize(query)
        guard !normalized.isEmpty else { return }
        var list = load().filter { $0.caseInsensitiveCompare(normalized) != .orderedSame }
        list.insert(normalized, at: 0)
        persist(Array(list.prefix(maxRecentSearches)))
    }

    public func remove(_ query: String) {
        let list = load().filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        persist(list)
    }

    public func clear() {
        preferences.set("", for: Self.key)
    }

    private func persist(_ list: [String]) {
        preferences.set(list.joined(separator: "\n"), for: Self.key)
    }
}
