import AppFoundation
import Foundation
@testable import ProfileKit

// MARK: - Cüzdan özeti okuma portu fake'i (current-value replay'li akış)

final class FakeWalletSummary: WalletSummaryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var summary: WalletSummary
    private let multicast = AsyncMulticast<WalletSummary>()

    init(_ summary: WalletSummary = .empty) {
        self.summary = summary
        multicast.send(summary)
    }

    /// Testten cüzdan değişimi (başka cihazdan satın alma/VIP) yayınlar.
    func set(_ newValue: WalletSummary) {
        lock.withLock { summary = newValue }
        multicast.send(newValue)
    }

    func currentSummary() async -> WalletSummary {
        lock.withLock { summary }
    }

    func summaryUpdates() -> AsyncStream<WalletSummary> {
        multicast.subscribe()
    }
}

// MARK: - Gate'li tercih deposu (atomik-olmayan persist penceresini deterministik açığa çıkarır)

/// Belirli bir String değeri ilk kez `set` edilirken SENKRON bekleten `PreferencesStoring`. Bir
/// yazarı persist anında bloklayıp başka bir yazarı araya sokarak review #7'deki sıralama yarışını
/// deterministik kurar (kilit dışı persist ↔ atomik persist ayrımı).
final class GatedPreferences: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: any PreferenceValue] = [:]
    private let gatedString: String
    private let watchString: String
    private var didGate = false

    /// `gatedString` persist'e ULAŞTIĞINDA sinyal verir (yazar artık gate'te bloklu).
    let reachedGate = DispatchSemaphore(value: 0)
    /// `watchString` persist EDİLDİĞİNDE sinyal verir.
    let watchPersisted = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    init(gate gatedString: String, signalOnPersist watchString: String) {
        self.gatedString = gatedString
        self.watchString = watchString
    }

    func releaseGate() {
        releaseSignal.signal()
    }

    func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V {
        lock.withLock { storage[key.name] as? V ?? key.default }
    }

    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        let str = value as? String
        let shouldGate = lock.withLock { () -> Bool in
            guard str == gatedString, !didGate else { return false }
            didGate = true
            return true
        }
        if shouldGate {
            reachedGate.signal()
            releaseSignal.wait()
        }
        lock.withLock { storage[key.name] = value }
        if str == watchString {
            watchPersisted.signal()
        }
    }

    func removeValue(for key: PreferenceKey<some PreferenceValue>) {
        lock.withLock { storage[key.name] = nil }
    }
}

// MARK: - Gate'li cüzdan portu (load snapshot ↔ canlı stream clobber yarışı)

/// `currentSummary()` (load'ın snapshot okuması) serbest bırakılana kadar bekleten cüzdan portu;
/// canlı `summaryUpdates()` ise TAZE değeri hemen replay eder. load'ın eski snapshot'ının canlı
/// stream'in taze değerini clobber etmesi review #12'de deterministik kurulur.
final class GatedWallet: WalletSummaryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private let snapshot: WalletSummary
    private let multicast = AsyncMulticast<WalletSummary>()

    init(snapshot: WalletSummary, live: WalletSummary) {
        self.snapshot = snapshot
        multicast.send(live) // stream replay = taze değer
    }

    func releaseSnapshot() {
        lock.withLock { released = true }
    }

    func currentSummary() async -> WalletSummary {
        while !lock.withLock({ released }) {
            await Task.yield()
        }
        return snapshot // load'ın göreceği ESKİ değer
    }

    func summaryUpdates() -> AsyncStream<WalletSummary> {
        multicast.subscribe()
    }
}

// MARK: - Sistem bildirim izni portu fake'i

final class FakeNotificationPermission: NotificationPermissionStatusProviding, @unchecked Sendable {
    let isSystemNotificationPermissionGranted: Bool

    init(granted: Bool) {
        isSystemNotificationPermissionGranted = granted
    }
}

// MARK: - Delegate spy'ları

@MainActor
final class ProfileDelegateSpy: ProfileDelegate {
    var accountLinking = 0
    var reauth: [AuthProvider] = []
    var coinStore = 0
    var vip: [Bool] = []
    var watchHistory = 0
    var settings = 0
    var notificationCenter = 0
    var support = 0

    func profileRequestsAccountLinking() {
        accountLinking += 1
    }

    func profileRequestsReauthentication(provider: AuthProvider) {
        reauth.append(provider)
    }

    func profileOpensCoinStore() {
        coinStore += 1
    }

    func profileOpensVIP(isSubscribed: Bool) {
        vip.append(isSubscribed)
    }

    func profileOpensWatchHistory() {
        watchHistory += 1
    }

    func profileOpensSettings() {
        settings += 1
    }

    func profileOpensNotificationCenter() {
        notificationCenter += 1
    }

    func profileOpensSupport() {
        support += 1
    }
}

@MainActor
final class SettingsDelegateSpy: SettingsDelegate {
    var accountManagement = 0
    var signOut = 0
    var accountDeletion = 0
    var legalPages: [LegalPage] = []
    var systemNotificationSettings = 0

    func settingsOpensAccountManagement() {
        accountManagement += 1
    }

    func settingsRequestsSignOut() {
        signOut += 1
    }

    func settingsRequestsAccountDeletion() {
        accountDeletion += 1
    }

    func settingsOpensLegalPage(_ page: LegalPage) {
        legalPages.append(page)
    }

    func settingsOpensSystemNotificationSettings() {
        systemNotificationSettings += 1
    }
}

// MARK: - Deterministik akış bekleme (aynı MainActor executor'da yield ederek gözlem görevini işler)

@MainActor
func eventually(iterations: Int = 500, _ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< iterations {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}
