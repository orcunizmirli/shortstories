import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// "≤1 bekleyen unlock" invariantı (06 §6.4) aktör-reentrancy'de: unlock(A) uçuştayken hesap-değişimi
/// reset() + araya giren unlock(B) olursa, A'nın epoch-fenced `defer`'i B'nin pendingUnlock marker'ını
/// SİLMEMELİDİR. WalletKit adversarial bug-hunt (LOW CONFIRMED) — çift-harcama yok (server-otoritatif +
/// version-monotonic + idempotency), ama invariant düşerse 3. eşzamanlı unlock araya girebilir.
struct WalletStorePendingUnlockTests {
    private actor CallOrder {
        private var value = 0
        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    @Test func midFlightResetSonrasiEskiUnlockDeferBaskaMarkeriSilmez() async {
        let remote = FakeWalletRemote()
        let gateA = AsyncGate()
        let gateB = AsyncGate()
        let order = CallOrder()
        // 1. çağrı (A) gateA'da, 2. çağrı (B) gateB'de asılı; sonraki çağrılar (C) bloklamaz.
        remote.unlockGate = {
            switch await order.next() {
            case 0: await gateA.wait()
            case 1: await gateB.wait()
            default: break
            }
        }
        remote.unlockResults = [
            .success(.unlocked(
                record: .fixture(episode: "ep_A", coinsSpent: 10),
                wallet: .fixture(purchased: 100, version: 10),
                transactions: []
            )),
            .success(.unlocked(
                record: .fixture(episode: "ep_B", coinsSpent: 10),
                wallet: .fixture(purchased: 90, version: 11),
                transactions: []
            ))
        ]
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))

        // (1) unlock(A) uçuşta (gateA'da asılı) → pendingUnlock = A.
        let taskA = Task { await store.unlock(episodeID: EpisodeID("ep_A"), expectedPrice: 10, idempotencyKey: "k1") }
        await waitUntil { remote.unlockCallCount == 1 }

        // (2) Hesap değişimi: reset() → pendingUnlock = nil, epoch++.
        await store.reset()

        // (3) unlock(B) uçuşta (gateB'de asılı) → pendingUnlock = B.
        let taskB = Task { await store.unlock(episodeID: EpisodeID("ep_B"), expectedPrice: 10, idempotencyKey: "k1") }
        await waitUntil { remote.unlockCallCount == 2 }

        // (4) A çözülür → epoch-fenced conflict → defer çalışır (B'nin marker'ını SİLMEMELİ).
        await gateA.open()
        let resultA = await taskA.value
        #expect(resultA == .failed(.wallet(.transactionConflict)))

        // (5) B hâlâ uçuşta → 3. unlock çakışma dönmeli (marker B korundu). Eski koşulsuz `defer` B'yi
        //     sildiğinden guard geçer, conflict DÖNMEZ → RED.
        let resultC = await store.unlock(episodeID: EpisodeID("ep_C"), expectedPrice: 10, idempotencyKey: "k1")
        #expect(resultC == .failed(.wallet(.transactionConflict)))

        // Temizlik: B'yi serbest bırak (task sızıntısı olmasın).
        await gateB.open()
        _ = await taskB.value
    }
}
