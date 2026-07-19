import AppFoundation
import Foundation
@testable import ProfileKit

// MARK: - Deterministic suspension primitive (SS-144 concurrency/reentrancy tests)

/// Deterministik askı primitifi (DiscoverKit `CallGate` deseninin ProfileKit karşılığı).
///
/// Çağıran `await gate.wait(label)` ile `label`e varır ve test `gate.open(label)` çağırana dek
/// askıda kalır. Test, uçuştaki çağıranlarla `await gate.arrivals(label, n)` ile eşitlenir — en az
/// `n` çağıran `label`e vardığında döner. Continuation'lar HER ZAMAN kilit DIŞINDA resume edilir;
/// böylece resume edilen görev kilide senkron yeniden giremez. Bu, model'in `await gateway.*`
/// noktalarındaki aktör-reentrancy'sini test'in SEÇTİĞİ sırada deterministik kurgulamayı sağlar.
final class CallGate: @unchecked Sendable {
    private struct ArrivalWaiter {
        let label: String
        let threshold: Int
        let cont: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var openLabels: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var arrived: [String: Int] = [:]
    private var arrivalWaiters: [ArrivalWaiter] = []

    /// `label`e varır ve açılana dek askıya alır.
    func wait(_ label: String) async {
        let (arrivalConts, alreadyOpen): ([CheckedContinuation<Void, Never>], Bool) = lock.withLock {
            arrived[label, default: 0] += 1
            let count = arrived[label] ?? 0
            let ready = arrivalWaiters.filter { $0.label == label && $0.threshold <= count }
            arrivalWaiters.removeAll { $0.label == label && $0.threshold <= count }
            return (ready.map(\.cont), openLabels.contains(label))
        }
        arrivalConts.forEach { $0.resume() }
        if alreadyOpen {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let openNow: Bool = lock.withLock {
                if openLabels.contains(label) {
                    return true
                }
                waiters[label, default: []].append(cont)
                return false
            }
            if openNow {
                cont.resume()
            }
        }
    }

    /// `label`de bekleyen mevcut ve gelecekteki tüm çağıranları serbest bırakır.
    func open(_ label: String) {
        let conts: [CheckedContinuation<Void, Never>] = lock.withLock {
            openLabels.insert(label)
            let waiting = waiters[label] ?? []
            waiters[label] = nil
            return waiting
        }
        conts.forEach { $0.resume() }
    }

    /// En az `threshold` çağıran `label`e varana dek bekler.
    func arrivals(_ label: String, _ threshold: Int = 1) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let ready: Bool = lock.withLock {
                if arrived[label, default: 0] >= threshold {
                    return true
                }
                arrivalWaiters.append(ArrivalWaiter(label: label, threshold: threshold, cont: cont))
                return false
            }
            if ready {
                cont.resume()
            }
        }
    }
}

// MARK: - Askıya alınabilir bildirim gateway'i (interleaving kurgusu)

/// `NotificationsGateway` fake'i — her çağrı (fetch/delete/markRead/markAllRead) yöntem-başına
/// artan bir indeks alır ve etiketi (`"fetch#0"`, `"delete#0"`, …) `gatedLabels`teyse bir
/// `CallGate`de askıya alınır. Test, op A'yı başlatıp askıda tutarken op B'yi çalıştırıp
/// continuation'ları SEÇTİĞİ sırada `open` ederek deterministik interleaving kurar (mevcut
/// senkron-kilitli fake yarışı ÜRETEMEZ — verifier tespiti). Sonuç (sayfa/hata) gate açıldıktan
/// SONRA okunur; böylece test, çağrı askıdayken `setFirstPage`/`setDeleteError` ile sunucu
/// anlık görüntüsünü değiştirebilir.
final class GatedNotificationsGateway: NotificationsGateway, @unchecked Sendable {
    let gate = CallGate()
    private let lock = NSLock()
    private let gatedLabels: Set<String>

    private var firstPage = NotificationsPage(items: [], nextCursor: nil)
    private var pagesByCursor: [String: NotificationsPage] = [:]
    private var fetchError: AppError?
    private var deleteError: AppError?
    private var markReadError: AppError?
    private var markAllReadError: AppError?

    private var fetchIndex = 0
    private var deleteIndex = 0
    private var markReadIndex = 0
    private var markAllReadIndex = 0

    private(set) var fetchedCursors: [String?] = []
    private(set) var deletedIDs: [NotificationID] = []
    private(set) var markReadCalls: [[NotificationID]] = []
    private(set) var markAllReadCallCount = 0

    init(gatedLabels: Set<String> = []) {
        self.gatedLabels = gatedLabels
    }

    // MARK: Kurulum (çağrı askıdayken de güvenle çağrılabilir — sonuç gate sonrası okunur)

    func setFirstPage(_ page: NotificationsPage) {
        lock.withLock { firstPage = page }
    }

    func setPage(_ page: NotificationsPage, forCursor cursor: String) {
        lock.withLock { pagesByCursor[cursor] = page }
    }

    func setFetchError(_ error: AppError?) {
        lock.withLock { fetchError = error }
    }

    func setDeleteError(_ error: AppError?) {
        lock.withLock { deleteError = error }
    }

    func setMarkAllReadError(_ error: AppError?) {
        lock.withLock { markAllReadError = error }
    }

    func setMarkReadError(_ error: AppError?) {
        lock.withLock { markReadError = error }
    }

    // MARK: NotificationsGateway

    func fetch(cursor: String?) async throws -> NotificationsPage {
        let index: Int = lock.withLock {
            fetchedCursors.append(cursor)
            let current = fetchIndex
            fetchIndex += 1
            return current
        }
        let label = "fetch#\(index)"
        if gatedLabels.contains(label) {
            await gate.wait(label)
        }
        return try lock.withLock {
            if let fetchError {
                throw fetchError
            }
            guard let cursor else { return firstPage }
            return pagesByCursor[cursor] ?? NotificationsPage(items: [], nextCursor: nil)
        }
    }

    func delete(id: NotificationID) async throws {
        let index: Int = lock.withLock {
            deletedIDs.append(id)
            let current = deleteIndex
            deleteIndex += 1
            return current
        }
        let label = "delete#\(index)"
        if gatedLabels.contains(label) {
            await gate.wait(label)
        }
        try lock.withLock {
            if let deleteError {
                throw deleteError
            }
        }
    }

    func markRead(ids: [NotificationID]) async throws {
        let index: Int = lock.withLock {
            markReadCalls.append(ids)
            let current = markReadIndex
            markReadIndex += 1
            return current
        }
        let label = "markRead#\(index)"
        if gatedLabels.contains(label) {
            await gate.wait(label)
        }
        try lock.withLock {
            if let markReadError {
                throw markReadError
            }
        }
    }

    func markAllRead() async throws {
        let index: Int = lock.withLock {
            markAllReadCallCount += 1
            let current = markAllReadIndex
            markAllReadIndex += 1
            return current
        }
        let label = "markAllRead#\(index)"
        if gatedLabels.contains(label) {
            await gate.wait(label)
        }
        try lock.withLock {
            if let markAllReadError {
                throw markAllReadError
            }
        }
    }
}
