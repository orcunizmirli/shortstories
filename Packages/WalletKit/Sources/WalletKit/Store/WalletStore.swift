import AppFoundation
import Foundation

/// Cüzdan durumu ve kilit açma akışının otoritatif istemci-tarafı sahibi (SS-092/095/097).
/// `actor` (kanon §2). Sorumluluklar:
/// - Bakiye state'i; her mutasyon SUNUCU snapshot'ından SET edilir (asla lokal aritmetik).
/// - `version` monoton-artan guard (out-of-order + idempotent kredi koruması).
/// - Optimistic kilit açma: earned-önce ön-düşüm + server reddinde ROLLBACK.
/// - Aynı anda en fazla 1 bekleyen unlock (06 §6.4).
/// - `EntitlementChecking` (R8): PlayerKit kilit kontrolü buradan beslenir.
/// - Entitlement + bakiye değişim yayını (AsyncStream; ≤5 sn hedefi push tabanlı).
public actor WalletStore: EntitlementChecking {
    private let remote: any WalletRemoting
    private let analytics: any AnalyticsTracking
    private let log: any Logging
    private let makeIdempotencyKey: @Sendable () -> String
    private let now: @Sendable () -> Date

    private var snapshot: WalletSnapshot
    private var hasServerSnapshot = false
    private var subscription: SubscriptionStatus
    private var hasServerSubscription = false
    private var storeKitOptimisticVIP = false
    private var unlockedEpisodes: Set<EpisodeID> = []
    private var pendingUnlock: EpisodeID?

    private let entitlementBroadcast = AsyncMulticast<EntitlementSnapshot>()
    private let balanceBroadcast = AsyncMulticast<CoinBalance>()

    public init(
        remote: any WalletRemoting,
        analytics: any AnalyticsTracking,
        log: any Logging,
        now: @escaping @Sendable () -> Date = { Date() },
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.remote = remote
        self.analytics = analytics
        self.log = log
        self.now = now
        self.makeIdempotencyKey = makeIdempotencyKey
        subscription = .none
        snapshot = WalletSnapshot(
            balance: .zero,
            earnedExpiringSoon: nil,
            firstTopUpEligible: false,
            updatedAt: now(),
            version: Int.min
        )
    }

    // MARK: - Okumalar

    public func currentBalance() -> CoinBalance {
        snapshot.balance
    }

    public func currentSnapshot() -> WalletSnapshot {
        snapshot
    }

    public func subscriptionStatus() -> SubscriptionStatus {
        subscription
    }

    public func isEpisodeUnlocked(_ episodeID: EpisodeID) -> Bool {
        unlockedEpisodes.contains(episodeID)
    }

    // MARK: - EntitlementChecking (R8)

    /// PlayerKit ön-kontrolü (04 §9.1): VIP tüm bölümleri açar; değilse daha önce açılmış mı.
    /// Oynatma yetkisinin doğruluk kaynağı yine sunucudur (`POST /playback/authorize`).
    public func hasAccess(to episodeID: EpisodeID) async -> Bool {
        subscription.grantsFullAccess || unlockedEpisodes.contains(episodeID)
    }

    // MARK: - Yayınlar (SS-097)

    public nonisolated func entitlementUpdates() -> AsyncStream<EntitlementSnapshot> {
        entitlementBroadcast.subscribe()
    }

    public nonisolated func balanceUpdates() -> AsyncStream<CoinBalance> {
        balanceBroadcast.subscribe()
    }

    // MARK: - Sunucu senkronu

    /// `GET /wallet` + `GET /subscription` — otoritatif tazeleme (06 §4.5).
    public func refresh() async {
        do {
            try await applyWallet(remote.fetchWallet())
        } catch {
            log.error("wallet refresh failed: \(String(describing: error))")
        }
        do {
            try await applySubscription(remote.fetchSubscription())
        } catch {
            log.error("subscription refresh failed: \(String(describing: error))")
        }
    }

    /// Bakiye snapshot'ı uygular (version-guard). PurchaseCoordinator kredilerde de kullanır.
    public func apply(walletSnapshot incoming: WalletSnapshot) {
        applyWallet(incoming)
    }

    /// Abonelik durumunu uygular ve entitlement değişimini yayınlar.
    public func apply(subscription incoming: SubscriptionStatus) {
        applySubscription(incoming)
    }

    /// StoreKit `currentEntitlements`'tan iyimser VIP tohumlar (06 §4.5): yalnız sunucu
    /// aboneliği henüz gelmemişken. Sunucu snapshot'ı geldiğinde ezilir; uyuşmazlık loglanır.
    public func seedEntitlementFromStoreKit(hasActiveSubscription: Bool) {
        guard !hasServerSubscription, hasActiveSubscription else { return }
        storeKitOptimisticVIP = true
        subscription = .optimisticVIP
        broadcastEntitlement()
    }

    // MARK: - Kilit açma (SS-095)

    /// UI'ın harcamadan ÖNCEKİ erken uyarısı için saf ön-kontrol (kanon §5): "yeterli mi +
    /// hangi kova". Bakiyeyi MUTASYONA UĞRATMAZ, yayınlamaz; yalnız mevcut snapshot'ı okur.
    /// Otoritatif düşüm SUNUCUDADIR — bu yalnız iyimser UI ipucudur.
    public func spendPreview(for amount: Int) -> SpendPlan {
        SpendPlanner.plan(spending: amount, from: snapshot.balance)
    }

    /// İyimser kilit açma — iyimserlik BAKİYEDE DEĞİL, UNLOCK DURUMUNDA (kanon §5; 05 §5.2;
    /// 06 §2.4 kural 3: istemci bakiyeyi ASLA lokal aritmetikle güncellemez). Akış:
    ///   (a) bölümü hemen açık işaretle → kullanıcı bölüme anında girebilir (entitlement state),
    ///   (b) coin bakiyesi YALNIZ sunucu snapshot'ından SET edilir (lokal çıkarma/yayın YOK),
    ///   (c) server reddinde (INSUFFICIENT_COINS/PRICE_CHANGED) iyimser kilit geri alınır ve
    ///       tipli sonuç döner.
    /// Aynı anda en fazla 1 bekleyen unlock (06 §6.4) — ikincisi `transactionConflict` döner.
    public func unlock(episodeID: EpisodeID, expectedPrice: Int) async -> UnlockResult {
        guard pendingUnlock == nil else {
            return .failed(.wallet(.transactionConflict))
        }
        pendingUnlock = episodeID
        defer { pendingUnlock = nil }

        // (a) İyimser entitlement: bölümü açık işaretle. Bakiyeye DOKUNULMAZ, yayınlanmaz —
        // balanceBroadcast'e lokal-düşülmüş ara değer ASLA düşmez.
        let wasUnlocked = unlockedEpisodes.contains(episodeID)
        if !wasUnlocked {
            markUnlocked(episodeID)
        }

        let key = makeIdempotencyKey()
        do {
            let outcome = try await remote.unlock(
                episodeID: episodeID,
                expectedPrice: expectedPrice,
                idempotencyKey: key
            )
            return handleUnlockOutcome(outcome, episodeID: episodeID, wasUnlocked: wasUnlocked)
        } catch let error as AppError {
            rollbackOptimisticUnlock(episodeID, wasUnlocked: wasUnlocked)
            log.error("unlock failed: \(String(describing: error))")
            return .failed(error)
        } catch {
            rollbackOptimisticUnlock(episodeID, wasUnlocked: wasUnlocked)
            return .failed(.unexpected(underlying: String(describing: error)))
        }
    }

    private func handleUnlockOutcome(
        _ outcome: UnlockOutcome,
        episodeID: EpisodeID,
        wasUnlocked: Bool
    ) -> UnlockResult {
        switch outcome {
        case let .unlocked(record, wallet, _):
            // (b) Server-otoritatif snapshot bakiyeyi SET eder (lokal çıkarma YOK); kilit kalıcı.
            applyWallet(wallet)
            markUnlocked(record.episodeID)
            analytics.track(
                "unlock_success",
                parameters: [
                    "episode_id": .string(record.episodeID.rawValue),
                    "coins_spent": .int(record.coinsSpent),
                    "method": .string(record.method.rawValue)
                ]
            )
            return .success(record)
        case let .insufficientCoins(shortfall, wallet):
            // (c) İyimser kilidi geri al; server snapshot verdiyse bakiyeyi otoritatif tazele.
            rollbackOptimisticUnlock(episodeID, wasUnlocked: wasUnlocked)
            if let wallet {
                applyWallet(wallet)
            }
            analytics.track(
                "unlock_insufficient_coins",
                parameters: ["episode_id": .string(episodeID.rawValue)]
            )
            return .insufficientCoins(shortfall: shortfall)
        case let .priceChanged(currentPrice):
            rollbackOptimisticUnlock(episodeID, wasUnlocked: wasUnlocked)
            return .priceChanged(currentPrice: currentPrice)
        }
    }

    /// İyimser kilidi geri alır — yalnız BU çağrıda eklenen kilidi kaldırır (bölüm zaten
    /// açıksa dokunmaz). Bakiye lokal değişmediğinden yalnız entitlement yayını gerekir.
    private func rollbackOptimisticUnlock(_ episodeID: EpisodeID, wasUnlocked: Bool) {
        guard !wasUnlocked else { return }
        unlockedEpisodes.remove(episodeID)
        broadcastEntitlement()
    }

    // MARK: - İç uygulayıcılar

    private func applyWallet(_ incoming: WalletSnapshot) {
        // version-guard (05 §2.5): eşit veya daha yeni snapshot uygulanır; eski atılır.
        // Server snapshot'ları mutlak bakiyeyi SET eder → aynı transaction iki kez gelse bile
        // (idempotent kredi) çift kredi YAZILMAZ.
        guard !hasServerSnapshot || incoming.version >= snapshot.version else {
            log.debug("stale wallet snapshot dropped (v\(incoming.version) < v\(snapshot.version))")
            return
        }
        snapshot = incoming
        hasServerSnapshot = true
        balanceBroadcast.send(incoming.balance)
    }

    /// Monotonluk guard (applyWallet ile simetri; out-of-order koruması): server zaten bir subscription
    /// snapshot'ı verdiyse ve HEM mevcut HEM gelen `updatedAt` taşıyorsa, daha ESKİ snapshot bayattır —
    /// uçuşta kalmış non-VIP fetch'in taze VIP'i EZMESİNİ engeller. `updatedAt` yoksa (nil) guard atlanır →
    /// son-yazan-kazanır (geriye uyum; downgrade/expiry akışları korunur).
    private func isStaleSubscription(_ incoming: SubscriptionStatus) -> Bool {
        guard hasServerSubscription,
              let incomingAt = incoming.updatedAt,
              let currentAt = subscription.updatedAt
        else { return false }
        return incomingAt < currentAt
    }

    private func applySubscription(_ incoming: SubscriptionStatus) {
        guard !isStaleSubscription(incoming) else {
            log.debug("stale subscription snapshot dropped (updatedAt \(String(describing: incoming.updatedAt)))")
            return
        }
        if storeKitOptimisticVIP, !incoming.isVIP {
            // Lokal (StoreKit) VIP diyor ama server hayır → server kazanır, uyuşmazlık loglanır (06 §4.5).
            analytics.track(
                "entitlement_mismatch",
                parameters: ["local_vip": .bool(true), "server_vip": .bool(false)]
            )
            log.info("entitlement mismatch: local VIP but server not — server wins")
        }
        storeKitOptimisticVIP = false
        hasServerSubscription = true
        subscription = incoming
        broadcastEntitlement()
    }

    private func markUnlocked(_ episodeID: EpisodeID) {
        let (inserted, _) = unlockedEpisodes.insert(episodeID)
        if inserted {
            broadcastEntitlement(lastUnlocked: episodeID)
        }
    }

    private func broadcastEntitlement(lastUnlocked: EpisodeID? = nil) {
        entitlementBroadcast.send(
            EntitlementSnapshot(
                isVIP: subscription.grantsFullAccess,
                vipExpiresAt: subscription.expiresAt,
                isInGracePeriod: subscription.isInGracePeriod,
                lastUnlockedEpisode: lastUnlocked
            )
        )
    }
}
