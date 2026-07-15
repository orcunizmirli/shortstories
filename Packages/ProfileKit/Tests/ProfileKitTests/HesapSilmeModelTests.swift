import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ProfileKit

@MainActor
@Suite("SS-133 HesapSilmeModel (çift-onay, geri-alma, veri talebi, analitik)")
struct HesapSilmeModelTests {
    private func makeModel(
        deletion: FakeAccountDeletion = FakeAccountDeletion(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: HesapSilmeDelegateSpy
    ) -> HesapSilmeModel {
        HesapSilmeModel(deletion: deletion, analytics: analytics, delegate: delegate)
    }

    private func deleteEvents(_ analytics: MockAnalytics) -> [String] {
        analytics.eventNames.filter { $0.hasPrefix("account_delete_") }
    }

    // MARK: - Başlangıç

    @Test func startsIdle() {
        let model = makeModel(delegate: HesapSilmeDelegateSpy())
        #expect(model.deletionState == .idle)
        #expect(model.dataExportState == .idle)
    }

    // MARK: - Çift-onay kapısı

    @Test func requestDeletionOpensConfirmationOnly() {
        let deletion = FakeAccountDeletion()
        let analytics = MockAnalytics()
        let model = makeModel(deletion: deletion, analytics: analytics, delegate: HesapSilmeDelegateSpy())

        model.requestDeletion()

        #expect(model.deletionState == .confirming)
        #expect(deletion.deletionCallCount == 0) // backend'e gitmedi
        #expect(deleteEvents(analytics).isEmpty) // henüz started YOK
    }

    @Test func confirmWithoutRequestIsNoOp() {
        // Çift-onay: önce diyalog açılmadan confirmDeletion() backend'e GİTMEZ.
        let deletion = FakeAccountDeletion()
        let analytics = MockAnalytics()
        let model = makeModel(deletion: deletion, analytics: analytics, delegate: HesapSilmeDelegateSpy())

        model.confirmDeletion()

        #expect(model.deletionState == .idle)
        #expect(deletion.deletionCallCount == 0)
        #expect(deleteEvents(analytics).isEmpty)
    }

    @Test func cancelReturnsToIdle() {
        let deletion = FakeAccountDeletion()
        let model = makeModel(deletion: deletion, delegate: HesapSilmeDelegateSpy())
        model.requestDeletion()
        model.cancelDeletion()
        #expect(model.deletionState == .idle)
        #expect(deletion.deletionCallCount == 0)
    }

    // MARK: - Silme başarısı + geri-alma penceresi

    @Test func confirmDeletionCompletesWithUndoWindow() async {
        let analytics = MockAnalytics()
        let spy = HesapSilmeDelegateSpy()
        let deadline = Date(timeIntervalSince1970: 2_000_000)
        let receipt = AccountDeletionReceipt(undoDeadline: deadline, requiresStoreSubscriptionCancellation: true)
        let model = makeModel(
            deletion: FakeAccountDeletion(deletion: .success(receipt)),
            analytics: analytics,
            delegate: spy
        )

        model.requestDeletion()
        model.confirmDeletion()
        await model.pendingWork()

        #expect(model.deletionState == .completed(receipt))
        if case let .completed(surfaced) = model.deletionState {
            #expect(surfaced.hasUndoWindow) // geri-alma penceresi client'a taşındı
            #expect(surfaced.undoDeadline == deadline)
            #expect(surfaced.requiresStoreSubscriptionCancellation) // abonelik uyarısı taşındı
        }
        #expect(spy.completed == [receipt])
        #expect(deleteEvents(analytics) == ["account_delete_started", "account_delete_completed"])
    }

    @Test func deletionWithoutUndoWindow() async {
        let receipt = AccountDeletionReceipt(undoDeadline: nil, requiresStoreSubscriptionCancellation: false)
        let model = makeModel(
            deletion: FakeAccountDeletion(deletion: .success(receipt)),
            delegate: HesapSilmeDelegateSpy()
        )
        model.requestDeletion()
        model.confirmDeletion()
        await model.pendingWork()

        if case let .completed(surfaced) = model.deletionState {
            #expect(!surfaced.hasUndoWindow)
        } else {
            Issue.record("completed bekleniyordu")
        }
    }

    // MARK: - Silme hatası (completed ÜRETİLMEZ) + retry

    @Test func deletionFailureDoesNotCompleteAndRetryReopensConfirm() async {
        let analytics = MockAnalytics()
        let spy = HesapSilmeDelegateSpy()
        let model = makeModel(
            deletion: FakeAccountDeletion(deletion: .failure(TestFailure())),
            analytics: analytics,
            delegate: spy
        )

        model.requestDeletion()
        model.confirmDeletion()
        await model.pendingWork()

        #expect(model.deletionState == .failed(.deletionFailed))
        #expect(spy.completed.isEmpty)
        // started var, completed YOK (registry yalnız started/completed).
        #expect(deleteEvents(analytics) == ["account_delete_started"])

        // Retry → çift-onay yeniden.
        model.retryDeletion()
        #expect(model.deletionState == .confirming)
    }

    // MARK: - Veri indirme talebi (bağımsız alt-akış)

    @Test func dataDownloadRequestSucceedsIndependently() async {
        let spy = HesapSilmeDelegateSpy()
        let receipt = DataExportReceipt(deliveryEmailMasked: "j***@example.com")
        let model = makeModel(
            deletion: FakeAccountDeletion(export: .success(receipt)),
            delegate: spy
        )

        model.requestDataDownload()
        await model.pendingWork()

        #expect(model.dataExportState == .requested(receipt))
        // Silme durumu dokunulmadan idle kalır (bağımsızlık).
        #expect(model.deletionState == .idle)
        #expect(spy.completed.isEmpty)
    }

    @Test func dataDownloadFailure() async {
        let model = makeModel(
            deletion: FakeAccountDeletion(export: .failure(TestFailure())),
            delegate: HesapSilmeDelegateSpy()
        )
        model.requestDataDownload()
        await model.pendingWork()
        #expect(model.dataExportState == .failed)
    }

    // MARK: - Navigasyon

    @Test func dismissInvokesDelegate() {
        let spy = HesapSilmeDelegateSpy()
        let model = makeModel(delegate: spy)
        model.dismiss()
        #expect(spy.dismissed == 1)
    }

    // MARK: - Yıkıcı eylem: silme uçarken 'Vazgeç' ekranı kapatmaz (SS-133)

    @Test func dismissBlockedWhileDeleting() async {
        // Silme uçarken (.deleting spinner) 'Vazgeç' → dismiss ekranı KAPATMAMALI: kullanıcı iptal
        // ettiğini sanmasın; geri-alınamaz silme arka planda tamamlanmasın (delegate tetiklenmez).
        // Deterministik: MainActor'da confirmDeletion() ile dismiss() arasında suspend YOK → görev
        // gövdesi henüz koşmaz, state senkron `.deleting`'dir.
        let spy = HesapSilmeDelegateSpy()
        let model = makeModel(delegate: spy)

        model.requestDeletion()
        model.confirmDeletion()
        #expect(model.deletionState == .deleting)

        model.dismiss()
        #expect(spy.dismissed == 0) // silme uçarken ekran kapanmadı

        await model.pendingWork() // askıdaki silme görevini boşalt
    }

    // MARK: - Geri-alma penceresi geçmiş-tarih kontrolü (ertelenen ucuz düzeltme)

    @Test func undoWindowClosedWhenDeadlineInPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = AccountDeletionReceipt(
            undoDeadline: now.addingTimeInterval(-60), // geçmişte
            requiresStoreSubscriptionCancellation: false
        )
        let future = AccountDeletionReceipt(
            undoDeadline: now.addingTimeInterval(60), // gelecekte
            requiresStoreSubscriptionCancellation: false
        )
        let immediate = AccountDeletionReceipt(undoDeadline: nil, requiresStoreSubscriptionCancellation: false)

        // Geçmiş deadline → yanıltıcı "geri alabilirsin" gösterilmemeli.
        #expect(past.hasUndoWindow) // pencere VERİLDİ ama...
        #expect(past.isUndoWindowOpen(now: now) == false) // ...artık AÇIK değil
        #expect(future.isUndoWindowOpen(now: now))
        #expect(immediate.isUndoWindowOpen(now: now) == false)
    }
}
