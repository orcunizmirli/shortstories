import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ProfileKit

/// Ortak model kurucu (iki suite paylaşır; dosya-yerel). @MainActor — model init'i MainActor.
@MainActor
private func makeModel(
    gateway: FakeNotificationsGateway = FakeNotificationsGateway(),
    analytics: MockAnalytics = MockAnalytics(),
    delegate: NotificationCenterDelegateSpy = NotificationCenterDelegateSpy()
) -> NotificationCenterModel {
    NotificationCenterModel(gateway: gateway, analytics: analytics, delegate: delegate)
}

@MainActor
@Suite("SS-144 NotificationCenterModel — yükleme/sayfalama/okundu")
struct NotificationCenterLoadTests {
    // MARK: - Yükleme + boş/dolu durum

    @Test func loadEmptyPageTransitionsToEmptyLoaded() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .emptyLoaded)
        #expect(model.notifications.isEmpty)
        #expect(model.unreadCount == 0)
        #expect(model.canLoadMore == false)
    }

    @Test func loadWithItemsTransitionsToLoadedAndCountsUnread() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a", isRead: false),
                NotificationFactory.make(id: "b", isRead: true),
                NotificationFactory.make(id: "c", isRead: false)
            ],
            nextCursor: "cur2"
        ))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.notifications.count == 3)
        #expect(model.unreadCount == 2)
        #expect(model.canLoadMore == true)
        #expect(model.showsOfflineBanner == false)
    }

    @Test func onAppearTriggersLoadOnce() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        model.onAppear()
        model.onAppear() // ikinci çağrı yeni görev başlatmaz
        await model.pendingWork()
        #expect(model.notifications.count == 1)
        #expect(gateway.fetchedCursors == [nil])
    }

    // MARK: - Sayfalama (append + dedup)

    @Test func loadMoreAppendsAndDedupsByID() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [NotificationFactory.make(id: "a"), NotificationFactory.make(id: "b")],
            nextCursor: "cur2"
        ))
        gateway.setPage(
            // "b" örtüşen sayfa öğesi → dedup edilmeli.
            NotificationsPage(
                items: [NotificationFactory.make(id: "b"), NotificationFactory.make(id: "c")],
                nextCursor: nil
            ),
            forCursor: "cur2"
        )
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.loadMore()
        #expect(model.notifications.map(\.id.rawValue) == ["a", "b", "c"])
        #expect(model.canLoadMore == false)
        #expect(gateway.fetchedCursors == [nil, "cur2"])
    }

    @Test func loadMoreNoOpWhenNoCursor() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.loadMore()
        #expect(gateway.fetchedCursors == [nil]) // ikinci fetch YOK
    }

    // MARK: - markAllRead

    @Test func markAllReadFlipsEveryItemAndCallsGatewayOnce() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a", isRead: false),
                NotificationFactory.make(id: "b", isRead: false)
            ],
            nextCursor: nil
        ))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.markAllRead()
        let allRead = model.notifications.allSatisfy(\.isRead)
        #expect(allRead)
        #expect(model.unreadCount == 0)
        #expect(gateway.markAllReadCallCount == 1)
    }

    @Test func markAllReadNoOpWhenAllAlreadyRead() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a", isRead: true)], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.markAllRead()
        #expect(gateway.markAllReadCallCount == 0) // hepsi okundu → gateway çağrılmaz
    }

    @Test func markAllReadRevertsOnGatewayError() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a", isRead: false),
                NotificationFactory.make(id: "b", isRead: true)
            ],
            nextCursor: nil
        ))
        gateway.setMarkAllReadError(.network(.offline))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.markAllRead()
        // Telafi: her öğe ÖNCEKİ okunma durumuna döner.
        #expect(model.notifications.first { $0.id == NotificationID("a") }?.isRead == false)
        #expect(model.notifications.first { $0.id == NotificationID("b") }?.isRead == true)
        #expect(model.unreadCount == 1)
    }

    // MARK: - markRead (tek)

    @Test func markReadFlipsSingleItem() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a", isRead: false),
                NotificationFactory.make(id: "b", isRead: false)
            ],
            nextCursor: nil
        ))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.markRead(NotificationID("a"))
        #expect(model.notifications.first { $0.id == NotificationID("a") }?.isRead == true)
        #expect(model.notifications.first { $0.id == NotificationID("b") }?.isRead == false)
        #expect(model.unreadCount == 1)
        #expect(gateway.markReadCalls == [[NotificationID("a")]])
    }

    @Test func markReadRevertsOnGatewayError() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a", isRead: false)], nextCursor: nil))
        gateway.setMarkReadError(.unexpected(underlying: "boom"))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.markRead(NotificationID("a"))
        #expect(model.notifications.first { $0.id == NotificationID("a") }?.isRead == false)
        #expect(model.unreadCount == 1)
    }

    // MARK: - Analitik: notification_center_opened

    @Test func firstLoadTracksOpenedOnceWithUnreadCount() async {
        let analytics = MockAnalytics()
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a", isRead: false),
                NotificationFactory.make(id: "b", isRead: false)
            ],
            nextCursor: nil
        ))
        let model = makeModel(gateway: gateway, analytics: analytics)
        await model.load()
        await model.load() // ikinci yükleme yeniden atmaz
        let openedEvents = analytics.events.filter { $0.name == "notification_center_opened" }
        #expect(openedEvents.count == 1)
        #expect(openedEvents.first?.parameters["unread_count"] == .int(2))
    }
}

@MainActor
@Suite("SS-144 NotificationCenterModel — sil/offline/rota")
struct NotificationCenterMutationTests {
    // MARK: - delete (optimistik + telafi)

    @Test func deleteRemovesItemAndCallsGateway() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [NotificationFactory.make(id: "a"), NotificationFactory.make(id: "b")],
            nextCursor: nil
        ))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.delete(NotificationID("a"))
        #expect(model.notifications.map(\.id.rawValue) == ["b"])
        #expect(gateway.deletedIDs == [NotificationID("a")])
    }

    @Test func deleteLastItemTransitionsToEmptyLoaded() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.delete(NotificationID("a"))
        #expect(model.notifications.isEmpty)
        #expect(model.loadState == .emptyLoaded)
    }

    @Test func deleteRevertsToOriginalPositionOnGatewayError() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(
            items: [
                NotificationFactory.make(id: "a"),
                NotificationFactory.make(id: "b"),
                NotificationFactory.make(id: "c")
            ],
            nextCursor: nil
        ))
        gateway.setDeleteError(.network(.offline))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.delete(NotificationID("b"))
        // Telafi: "b" orijinal (1) konumuna geri eklenir.
        #expect(model.notifications.map(\.id.rawValue) == ["a", "b", "c"])
    }

    @Test func deleteRevertRestoresLoadedFromEmpty() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        gateway.setDeleteError(.network(.offline))
        let model = makeModel(gateway: gateway)
        await model.load()
        await model.delete(NotificationID("a"))
        #expect(model.notifications.map(\.id.rawValue) == ["a"])
        #expect(model.loadState == .loaded) // emptyLoaded → telafi → loaded
    }

    // MARK: - Offline / hata → cache + banner

    @Test func offlineLoadWithoutCacheShowsErrorWithCacheAndBanner() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFetchError(.network(.offline))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .errorWithCache)
        #expect(model.showsOfflineBanner == true)
        #expect(model.notifications.isEmpty)
    }

    @Test func offlineReloadPreservesCachedListAndRaisesBanner() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load() // cache dolar
        gateway.setFetchError(.network(.offline))
        await model.load() // yenile → hata
        #expect(model.notifications.map(\.id.rawValue) == ["a"]) // cache KORUNUR
        #expect(model.loadState == .errorWithCache)
        #expect(model.showsOfflineBanner == true)
    }

    @Test func nonOfflineErrorDoesNotRaiseOfflineBanner() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFetchError(.unexpected(underlying: "500"))
        let model = makeModel(gateway: gateway)
        await model.load()
        #expect(model.loadState == .errorWithCache)
        #expect(model.showsOfflineBanner == false)
    }

    @Test func retryAfterErrorLoadsSuccessfully() async {
        let gateway = FakeNotificationsGateway()
        gateway.enqueueFetchError(.network(.offline)) // ilk fetch hata
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: nil))
        let model = makeModel(gateway: gateway)
        await model.load() // hata
        #expect(model.loadState == .errorWithCache)
        await model.load() // "Tekrar Dene" → başarı
        #expect(model.loadState == .loaded)
        #expect(model.notifications.map(\.id.rawValue) == ["a"])
        #expect(model.showsOfflineBanner == false)
    }

    @Test func loadMoreErrorKeepsListAndCursorForRetry() async {
        let gateway = FakeNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [NotificationFactory.make(id: "a")], nextCursor: "cur2"))
        let model = makeModel(gateway: gateway)
        await model.load()
        gateway.setFetchError(.network(.offline))
        await model.loadMore() // sayfa hata
        #expect(model.notifications.map(\.id.rawValue) == ["a"]) // liste YIKILMAZ
        #expect(model.canLoadMore == true) // cursor korunur → retry mümkün
        #expect(model.showsOfflineBanner == true)
        // Retry başarısı ekler.
        gateway.setFetchError(nil)
        gateway.setPage(
            NotificationsPage(items: [NotificationFactory.make(id: "b")], nextCursor: nil),
            forCursor: "cur2"
        )
        await model.loadMore()
        #expect(model.notifications.map(\.id.rawValue) == ["a", "b"])
        #expect(model.canLoadMore == false)
    }

    // MARK: - Satır dokunuşu → rota ayrımı (App fallback işareti)

    @Test func openValidRouteDispatchesToDelegateAndTracks() {
        let analytics = MockAnalytics()
        let delegate = NotificationCenterDelegateSpy()
        let model = makeModel(analytics: analytics, delegate: delegate)
        let notification = NotificationFactory.make(id: "a", type: .newEpisode, route: "series/s1/episode/2")
        model.open(notification)
        #expect(delegate.openedRoutes == ["series/s1/episode/2"])
        #expect(delegate.discoverFallbackCount == 0)
        #expect(analytics.events.contains {
            $0.name == "notification_item_tapped"
                && $0.parameters["type"] == .string("new_episode")
                && $0.parameters["route"] == .string("series/s1/episode/2")
        })
    }

    @Test func openInvalidRouteFallsBackToDiscover() {
        let delegate = NotificationCenterDelegateSpy()
        let model = makeModel(delegate: delegate)
        model.open(NotificationFactory.make(id: "a", route: "  "))
        #expect(delegate.discoverFallbackCount == 1)
        #expect(delegate.openedRoutes.isEmpty)
    }
}
