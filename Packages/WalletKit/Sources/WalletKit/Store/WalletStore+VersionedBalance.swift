import Foundation

/// Bakiye + `version` yayını (05 §2.5). RewardsKit OdulMerkezi başlığı version-monotonic uzlaştırır:
/// yalnız STRICTLY-NEWER version uygulanır → bayat düşük değer (pre-claim replay) düşürülür, MEŞRU düşüş
/// (spend, daha yüksek version) uygulanır. `versionedBalanceUpdates`, `balanceUpdates`'in versiyonlu
/// ikizidir; `broadcastBalance(from:)` her ikisini AYNI snapshot'tan besler (iki multicast drift etmez).
extension WalletStore {
    public nonisolated func versionedBalanceUpdates() -> AsyncStream<VersionedCoinBalance> {
        versionedBalanceBroadcast.subscribe()
    }

    /// Versiyonsuz + versiyonlu bakiye akışını TEK noktadan yayınlar (reset + applyWallet çağırır).
    /// `snapshot` parametreyle geçer → çekirdek durum `private` kalır (sink'ler yalnız `internal`).
    func broadcastBalance(from snapshot: WalletSnapshot) {
        balanceBroadcast.send(snapshot.balance)
        versionedBalanceBroadcast.send(VersionedCoinBalance(balance: snapshot.balance, version: snapshot.version))
    }
}
