import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ProfileKit

/// SS-144 NotificationCenterModel aktör-reentrancy / interleaving testleri (adversarial review F1–F5).
/// `GatedNotificationsGateway` her `await gateway.*` noktasını deterministik askıya alır; testler
/// op A'yı uçuşta tutarken op B'yi araya sokar → optimistik-telafi + jeton mantığının bayat anlık
/// görüntüyle sağlamlığını kilitler. @MainActor — model MainActor'da yaşar.
@MainActor
@Suite("SS-144 NotificationCenterModel — interleaving / reentrancy")
struct NotificationCenterConcurrencyTests {
    private func make(
        _ gateway: GatedNotificationsGateway,
        analytics: MockAnalytics = MockAnalytics()
    ) -> NotificationCenterModel {
        NotificationCenterModel(
            gateway: gateway,
            analytics: analytics,
            delegate: NotificationCenterDelegateSpy()
        )
    }

    private func note(_ id: String, isRead: Bool = false) -> AppNotification {
        NotificationFactory.make(id: id, isRead: isRead)
    }

    // MARK: - F1: uçuştaki refresh, sonradan başlayan loadMore tarafından düşürülmemeli

    @Test func loadMoreDoesNotSupersedeInFlightRefresh() async {
        let gateway = GatedNotificationsGateway(gatedLabels: ["fetch#1"])
        gateway.setFirstPage(NotificationsPage(items: [note("a"), note("b")], nextCursor: "cur2"))
        gateway.setPage(NotificationsPage(items: [note("c")], nextCursor: nil), forCursor: "cur2")
        let model = make(gateway)

        await model.load() // fetch#0 → [a, b]

        // Sunucu tazelendi: refresh farklı içerik döndürecek.
        gateway.setFirstPage(NotificationsPage(items: [note("x"), note("y")], nextCursor: "cur2"))
        let refreshTask = Task { await model.load() } // fetch#1 (gated)
        await gateway.gate.arrivals("fetch#1")

        // Refresh uçuştayken loadMore araya girer.
        let moreTask = Task { await model.loadMore() }
        await moreTask.value

        gateway.gate.open("fetch#1")
        await refreshTask.value

        // Refresh authoritative: bayat sayfa (c) bayat listeye (a,b) EKLENMEMELİ.
        #expect(model.notifications.map(\.id.rawValue) == ["x", "y"])
        #expect(!gateway.fetchedCursors.contains("cur2"))
    }

    // MARK: - F2: delete telafisi araya giren load ile YİNELENEN id / yanlış konum üretmemeli

    @Test func deleteCompensationAfterInterleavedLoadDoesNotDuplicate() async {
        let gateway = GatedNotificationsGateway(gatedLabels: ["delete#0"])
        gateway.setFirstPage(NotificationsPage(items: [note("a"), note("b"), note("c")], nextCursor: nil))
        let model = make(gateway)

        await model.load() // fetch#0 → [a, b, c]
        gateway.setDeleteError(.network(.offline))

        let deleteTask = Task { await model.delete(NotificationID("b")) } // delete#0 (gated) → optimistik [a, c]
        await gateway.gate.arrivals("delete#0")

        // Araya giren authoritative load (sunucu hâlâ b'yi ve yeni d'yi döndürür).
        gateway.setFirstPage(NotificationsPage(items: [note("a"), note("b"), note("c"), note("d")], nextCursor: nil))
        await model.load() // fetch#1

        gateway.gate.open("delete#0") // delete hata → telafi
        await deleteTask.value

        // Bayat index/dedupsuz insert YİNELENEN "b" ÜRETMEMELİ; authoritative liste kazanır.
        #expect(model.notifications.map(\.id.rawValue) == ["a", "b", "c", "d"])
        #expect(Set(model.notifications.map(\.id)).count == model.notifications.count)
    }

    // MARK: - F3: markAllRead telafisi araya giren load ile tazelenmiş listeyi ezmemeli

    @Test func markAllReadCompensationDoesNotClobberFreshList() async {
        let gateway = GatedNotificationsGateway(gatedLabels: ["markAllRead#0"])
        gateway.setFirstPage(NotificationsPage(items: [note("a", isRead: false), note("b", isRead: false)], nextCursor: nil))
        let model = make(gateway)

        await model.load() // fetch#0 → [a?, b?]
        gateway.setMarkAllReadError(.network(.offline))

        let markTask = Task { await model.markAllRead() } // gated → optimistik hepsi okundu
        await gateway.gate.arrivals("markAllRead#0")

        // Araya giren load: sunucu a'yı OKUNDU döndürür, b düşer.
        gateway.setFirstPage(NotificationsPage(items: [note("a", isRead: true)], nextCursor: nil))
        await model.load() // fetch#1 → [a(okundu)]

        gateway.gate.open("markAllRead#0") // markAllRead hata → telafi
        await markTask.value

        // Bayat previousReadByID a'yı yeniden OKUNMAMIŞ yapmamalı; taze durum korunur.
        #expect(model.notifications.map(\.id.rawValue) == ["a"])
        #expect(model.notifications.first?.isRead == true)
        #expect(model.unreadCount == 0)
    }

    // MARK: - F4: .errorWithCache iken son cache öğesi silinince boş-durum'a geçmeli

    @Test func deleteLastCachedItemInErrorStateTransitionsToEmpty() async {
        let gateway = GatedNotificationsGateway()
        gateway.setFirstPage(NotificationsPage(items: [note("a")], nextCursor: nil))
        let model = make(gateway)

        await model.load() // .loaded, [a]
        gateway.setFetchError(.network(.offline))
        await model.load() // .errorWithCache, cache [a] KORUNUR, banner

        #expect(model.loadState == .errorWithCache)
        await model.delete(NotificationID("a")) // deleteError yok → başarı

        #expect(model.notifications.isEmpty)
        // Boş liste → View "Henüz bildirimin yok" göstermeli, tam-ekran hata DEĞİL.
        #expect(model.loadState == .emptyLoaded)
    }

    // MARK: - F5: başarıyla silinen öğe, bayat sunucu snapshot'lı load ile DİRİLMEMELİ

    @Test func successfullyDeletedItemNotResurrectedByStaleLoad() async {
        let gateway = GatedNotificationsGateway(gatedLabels: ["fetch#1"])
        gateway.setFirstPage(NotificationsPage(items: [note("a"), note("b")], nextCursor: nil))
        let model = make(gateway)

        await model.load() // fetch#0 → [a, b]

        // Snapshot'ı silme'den ÖNCE alınan bayat refresh (sunucu a'yı hâlâ döndürür).
        let staleRefresh = Task { await model.load() } // fetch#1 (gated)
        await gateway.gate.arrivals("fetch#1")

        await model.delete(NotificationID("a")) // başarı → tombstone a, liste [b]
        #expect(model.notifications.map(\.id.rawValue) == ["b"])

        gateway.gate.open("fetch#1") // bayat refresh şimdi [a, b] yazmaya çalışır
        await staleRefresh.value

        // Tombstone filtresi a'yı DİRİLTMEMELİ.
        #expect(model.notifications.map(\.id.rawValue) == ["b"])
    }
}
