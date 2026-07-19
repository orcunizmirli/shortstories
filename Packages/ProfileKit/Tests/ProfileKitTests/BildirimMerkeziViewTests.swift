import Foundation
import SwiftUI
import Testing
@testable import ProfileKit

/// SS-144 BildirimMerkeziView görünürlük/snapshot-mantık testleri (deliverable 2). SwiftUI render
/// ETMEZ — View'ın saf karar yüzeyini (durum→bölüm, banner görünürlüğü, mark-all-read aktifliği,
/// okunmamış nokta, tip→ikon, göreli-zaman biçimi) doğrular. Bu yüzey `NotificationCenterModel`
/// durum makinesinin View'a yansımasını 02 §4.15 durum tablosuna kilitler.
@MainActor
@Suite("SS-144 BildirimMerkeziView — durum→bölüm görünürlüğü")
struct NotificationCenterSectionTests {
    typealias Section = BildirimMerkeziView.ContentSection

    // MARK: - Hangi durumda hangi bölüm (skeleton vs boş vs liste vs offline/hata)

    @Test func idleAndLoadingShowSkeleton() {
        #expect(BildirimMerkeziView.contentSection(loadState: .idle, hasNotifications: false, isOffline: false) == .skeleton)
        #expect(BildirimMerkeziView.contentSection(loadState: .loading, hasNotifications: false, isOffline: false) == .skeleton)
    }

    @Test func emptyLoadedShowsEmptyState() {
        let section = BildirimMerkeziView.contentSection(loadState: .emptyLoaded, hasNotifications: false, isOffline: false)
        #expect(section == .empty)
    }

    @Test func loadedWithItemsShowsList() {
        let section = BildirimMerkeziView.contentSection(loadState: .loaded, hasNotifications: true, isOffline: false)
        #expect(section == .list)
    }

    @Test func errorWithCachedItemsShowsListNotFullScreen() {
        // Cache VARSA hata/offline'da liste korunur (banner ayrı gelir).
        let offline = BildirimMerkeziView.contentSection(loadState: .errorWithCache, hasNotifications: true, isOffline: true)
        let generic = BildirimMerkeziView.contentSection(loadState: .errorWithCache, hasNotifications: true, isOffline: false)
        #expect(offline == .list)
        #expect(generic == .list)
    }

    @Test func errorWithEmptyCacheShowsFullScreenOfflineOrError() {
        // Cache YOKSA tam-ekran: offline'da offline, değilse hata (model ayrı state tutmaz).
        let offline = BildirimMerkeziView.contentSection(loadState: .errorWithCache, hasNotifications: false, isOffline: true)
        let generic = BildirimMerkeziView.contentSection(loadState: .errorWithCache, hasNotifications: false, isOffline: false)
        #expect(offline == .offline)
        #expect(generic == .error)
    }

    // MARK: - Offline banner yalnız cache'li liste üstünde

    @Test func offlineBannerVisibleOnlyOnCachedList() {
        #expect(BildirimMerkeziView.showsOfflineBanner(section: .list, modelShowsBanner: true))
        // Boş offline tam-ekran → banner + tam-ekran çift göstermez.
        #expect(!BildirimMerkeziView.showsOfflineBanner(section: .offline, modelShowsBanner: true))
        // Liste ama offline değil → banner yok.
        #expect(!BildirimMerkeziView.showsOfflineBanner(section: .list, modelShowsBanner: false))
        #expect(!BildirimMerkeziView.showsOfflineBanner(section: .skeleton, modelShowsBanner: true))
        #expect(!BildirimMerkeziView.showsOfflineBanner(section: .empty, modelShowsBanner: true))
    }

    // MARK: - "Tümünü okundu say" aktifliği

    @Test func markAllReadEnabledOnlyWhenUnreadExists() {
        #expect(BildirimMerkeziView.isMarkAllReadEnabled(unreadCount: 1))
        #expect(BildirimMerkeziView.isMarkAllReadEnabled(unreadCount: 9))
        #expect(!BildirimMerkeziView.isMarkAllReadEnabled(unreadCount: 0))
    }
}

@MainActor
@Suite("SS-144 NotificationRow — okunmamış nokta / ikon / erişilebilirlik")
struct NotificationRowTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Okunmamış nokta yalnız isRead=false'da

    @Test func unreadDotShownOnlyWhenUnread() {
        let unread = NotificationRow(notification: NotificationFactory.make(id: "a", isRead: false), now: now)
        let read = NotificationRow(notification: NotificationFactory.make(id: "b", isRead: true), now: now)
        #expect(unread.showsUnreadDot)
        #expect(!read.showsUnreadDot)
    }

    // MARK: - Tip → ikon (savunmacı unknown dahil)

    @Test func iconMapsPerType() {
        #expect(NotificationRow.iconSystemName(for: .newEpisode) == "play.rectangle.fill")
        #expect(NotificationRow.iconSystemName(for: .continueWatching) == "play.circle.fill")
        #expect(NotificationRow.iconSystemName(for: .coinReward) == "bitcoinsign.circle.fill")
        #expect(NotificationRow.iconSystemName(for: .recommendation) == "sparkles")
        #expect(NotificationRow.iconSystemName(for: .reward) == "gift.fill")
        #expect(NotificationRow.iconSystemName(for: .campaign) == "megaphone.fill")
        // Savunmacı: bilinmeyen tip öğe düşürmez → jenerik zil ikonu.
        #expect(NotificationRow.iconSystemName(for: .unknown) == "bell.fill")
    }

    // MARK: - F6: ikon glyph'i AX Dynamic Type'ta 32pt frame'i taşmamalı

    @Test func iconDynamicTypeCappedBelowAccessibilitySizes() {
        // İkon 32x32 sabit frame'de DS headingM (ölçekli) ile çizilir → AX4/AX5'te glyph taşabilir.
        // İkonun Dynamic Type üst sınırı erişilebilirlik boyutlarının ALTINDA olmalı (frame taşması yok).
        #expect(NotificationRow.iconMaxDynamicTypeSize <= .xxxLarge)
        #expect(NotificationRow.iconMaxDynamicTypeSize < .accessibility1)
    }

    // MARK: - Birleşik VoiceOver etiketi (satırda)

    @Test func accessibilityLabelCombinesTypeTitleBodyTimeAndUnread() {
        let row = NotificationRow(
            notification: NotificationFactory.make(
                id: "a",
                type: .newEpisode,
                title: "Yeni bölüm yayında",
                body: "Gölge Oyunu 8. bölüm",
                createdAt: now.addingTimeInterval(-3 * 60), // 3 dk önce
                isRead: false
            ),
            now: now
        )
        #expect(row.accessibilityLabel == "Yeni bölüm, Yeni bölüm yayında, Gölge Oyunu 8. bölüm, 3 dk, okunmadı")
    }

    @Test func accessibilityLabelOmitsUnreadWhenRead() {
        let row = NotificationRow(
            notification: NotificationFactory.make(
                id: "a",
                type: .campaign,
                title: "Kampanya",
                body: "Hafta sonu 2x coin",
                createdAt: now,
                isRead: true
            ),
            now: now
        )
        #expect(row.accessibilityLabel == "Kampanya, Kampanya, Hafta sonu 2x coin, şimdi")
        #expect(!row.accessibilityLabel.contains("okunmadı"))
    }
}

@Suite("SS-144 NotificationRelativeTime — göreli-zaman biçimi")
struct NotificationRelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func text(secondsAgo: TimeInterval) -> String {
        NotificationRelativeTime.string(for: now.addingTimeInterval(-secondsAgo), relativeTo: now)
    }

    @Test func subMinuteShowsSimdi() {
        #expect(text(secondsAgo: 0) == "şimdi")
        #expect(text(secondsAgo: 59) == "şimdi")
    }

    @Test func minutesBucket() {
        #expect(text(secondsAgo: 60) == "1 dk")
        #expect(text(secondsAgo: 3 * 60) == "3 dk")
        #expect(text(secondsAgo: 59 * 60) == "59 dk")
    }

    @Test func hoursBucket() {
        #expect(text(secondsAgo: 60 * 60) == "1 sa")
        #expect(text(secondsAgo: 23 * 60 * 60) == "23 sa")
    }

    @Test func daysBucket() {
        #expect(text(secondsAgo: 24 * 60 * 60) == "1 g")
        #expect(text(secondsAgo: 6 * 24 * 60 * 60) == "6 g")
    }

    @Test func weeksBucket() {
        #expect(text(secondsAgo: 7 * 24 * 60 * 60) == "1 hafta")
        #expect(text(secondsAgo: 21 * 24 * 60 * 60) == "3 hafta")
    }

    @Test func futureDateClampsToSimdi() {
        // Cihaz saati kayması → gelecekteki createdAt negatif süre gösterilmez.
        #expect(NotificationRelativeTime.string(for: now.addingTimeInterval(120), relativeTo: now) == "şimdi")
    }
}
