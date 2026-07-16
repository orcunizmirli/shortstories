import AppFoundation
import DiscoverKit
import Foundation
@testable import ShortSeriesApp

// SS-140/143 — Push testleri için test double'ları. Dış sistemler (DeviceTokenRegistering / UIApplication
// kaydı / UN yetki durumu) fake port'larla sürülür → gerçek APNs/UN OLMADAN koşar. Bu hedef CI'da
// KOŞMAZ (App target CI dışı); Xcode/lokal doğrulama içindir.

/// `DeviceTokenRegistering` casusu — kayıt/izin çağrılarını sırayla kaydeder.
final class SpyDeviceTokenRegistrar: DeviceTokenRegistering, @unchecked Sendable {
    struct Registration: Equatable {
        let token: String
        let optIn: Bool
    }

    private let lock = NSLock()
    private var registrationsStore: [Registration] = []
    private var optInUpdatesStore: [Bool] = []

    var registrations: [Registration] {
        lock.withLock { registrationsStore }
    }

    var optInUpdates: [Bool] {
        lock.withLock { optInUpdatesStore }
    }

    func registerToken(_ token: DeviceToken, optIn: Bool) async {
        lock.withLock { registrationsStore.append(Registration(token: token.hexString, optIn: optIn)) }
    }

    func updateOptIn(_ optIn: Bool) async {
        lock.withLock { optInUpdatesStore.append(optIn) }
    }
}

/// `RemoteNotificationRegistering` casusu — `registerForRemoteNotifications()` çağrı sayısı.
@MainActor
final class SpyRemoteNotificationRegistering: RemoteNotificationRegistering {
    private(set) var count = 0

    func registerForRemoteNotifications() {
        count += 1
    }
}

/// `NotificationAuthorizationReading` stub'ı — sabit yetki durumu döner.
struct StubAuthorizationReader: NotificationAuthorizationReading {
    let authorized: Bool

    func isAuthorized() async -> Bool {
        authorized
    }
}

/// Rota dağıtım casusu (PushService `dispatch` closure'u).
@MainActor
final class RouteDispatchSpy {
    private(set) var dispatched: [(route: DeepLinkRoute, source: DeepLinkSource)] = []

    func dispatch(_ route: DeepLinkRoute, _ source: DeepLinkSource) {
        dispatched.append((route, source))
    }
}
