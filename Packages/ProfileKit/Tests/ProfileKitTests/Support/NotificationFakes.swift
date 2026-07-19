import AppFoundation
import Foundation
@testable import ProfileKit

// MARK: - Bildirim ağ portu fake'i (SS-144, deliverable 4 — izole/deterministik)

/// `NotificationsGateway` fake'i: cursor→sayfa haritası, hata enjeksiyonu (fetch/markRead/
/// markAllRead/delete), "önce hata sonra başarı" fetch kuyruğu ve çağrı kaydı. Kilitli
/// (`@unchecked Sendable`) — model `await` ile MainActor dışından çağırabilir.
final class FakeNotificationsGateway: NotificationsGateway, @unchecked Sendable {
    private let lock = NSLock()

    // Yapılandırma (test kurar)
    private var firstPage = NotificationsPage(items: [], nextCursor: nil)
    private var pagesByCursor: [String: NotificationsPage] = [:]
    /// Sırayla tüketilen fetch hataları (retry testleri: fail → success). Boşsa `fetchError` geçerli.
    private var fetchErrorQueue: [AppError] = []
    private var fetchError: AppError?
    private var markReadError: AppError?
    private var markAllReadError: AppError?
    private var deleteError: AppError?

    // Kayıt (test doğrular)
    private(set) var fetchedCursors: [String?] = []
    private(set) var markReadCalls: [[NotificationID]] = []
    private(set) var markAllReadCallCount = 0
    private(set) var deletedIDs: [NotificationID] = []

    // MARK: Kurulum

    func setFirstPage(_ page: NotificationsPage) {
        lock.withLock { firstPage = page }
    }

    func setPage(_ page: NotificationsPage, forCursor cursor: String) {
        lock.withLock { pagesByCursor[cursor] = page }
    }

    func setFetchError(_ error: AppError?) {
        lock.withLock { fetchError = error }
    }

    func enqueueFetchError(_ error: AppError) {
        lock.withLock { fetchErrorQueue.append(error) }
    }

    func setMarkReadError(_ error: AppError?) {
        lock.withLock { markReadError = error }
    }

    func setMarkAllReadError(_ error: AppError?) {
        lock.withLock { markAllReadError = error }
    }

    func setDeleteError(_ error: AppError?) {
        lock.withLock { deleteError = error }
    }

    // MARK: NotificationsGateway

    func fetch(cursor: String?) async throws -> NotificationsPage {
        try lock.withLock {
            fetchedCursors.append(cursor)
            if !fetchErrorQueue.isEmpty {
                throw fetchErrorQueue.removeFirst()
            }
            if let fetchError {
                throw fetchError
            }
            guard let cursor else { return firstPage }
            return pagesByCursor[cursor] ?? NotificationsPage(items: [], nextCursor: nil)
        }
    }

    func markRead(ids: [NotificationID]) async throws {
        try lock.withLock {
            markReadCalls.append(ids)
            if let markReadError {
                throw markReadError
            }
        }
    }

    func markAllRead() async throws {
        try lock.withLock {
            markAllReadCallCount += 1
            if let markAllReadError {
                throw markAllReadError
            }
        }
    }

    func delete(id: NotificationID) async throws {
        try lock.withLock {
            deletedIDs.append(id)
            if let deleteError {
                throw deleteError
            }
        }
    }
}

// MARK: - Delegate spy

@MainActor
final class NotificationCenterDelegateSpy: NotificationCenterDelegate {
    private(set) var openedRoutes: [String] = []
    private(set) var discoverFallbackCount = 0

    func notificationCenterOpensRoute(_ route: String) {
        openedRoutes.append(route)
    }

    func notificationCenterFallsBackToDiscover() {
        discoverFallbackCount += 1
    }
}

// MARK: - Bildirim kurucu (test veri kolaylığı)

enum NotificationFactory {
    static func make(
        id: String,
        type: NotificationType = .newEpisode,
        title: String = "Başlık",
        body: String = "Gövde",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        route: String = "series/s1/episode/2",
        isRead: Bool = false
    ) -> AppNotification {
        AppNotification(
            id: NotificationID(id),
            type: type,
            title: title,
            body: body,
            createdAt: createdAt,
            route: route,
            isRead: isRead
        )
    }
}
