import AppFoundation
import Foundation

/// Cüzdan durumu ve kilit açma akışının otoritatif istemci-tarafı sahibi (SS-092/095/097). `actor`
/// (kanon §2). Sorumluluklar: bakiye state'i (her mutasyon SUNUCU snapshot'ından SET; lokal aritmetik
/// YOK); `version` monoton guard (out-of-order + idempotent kredi); optimistic kilit (earned-önce
/// ön-düşüm + server reddinde rollback); aynı anda ≤1 bekleyen unlock (06 §6.4); `EntitlementChecking`
/// (R8, PlayerKit kilit kontrolü); entitlement + bakiye değişim yayını (AsyncStream, ≤5 sn push).
public actor WalletStore: EntitlementChecking {
    private let remote: any WalletRemoting
    private let analytics: any AnalyticsTracking
    private let log: any Logging
    private let makeIdempotencyKey: @Sendable () -> String
    private let now: @Sendable () -> Date
    /// Kazanç-hızı danışma monitörü (SS-100). Earned-kese ARTIŞLARI raporlanır (`FraudSignalInterceptor`).
    /// `nil` = bağlı değil (F1/test). Yalnız GÖZLEM: bakiye/entitlement akışını ETKİLEMEZ.
    private let earnVelocityRecorder: (any EarnVelocityRecording)?

    private var snapshot: WalletSnapshot
    private var hasServerSnapshot = false
    private var subscription: SubscriptionStatus
    private var hasServerSubscription = false
    private var storeKitOptimisticVIP = false
    private var unlockedEpisodes: Set<EpisodeID> = []
    private var pendingUnlock: EpisodeID?
    /// Hesap epoch'u (§575 audit HIGH): her `reset()` artırır; uçuştaki önceki-hesap yanıtını fence eder
    /// (version-guard hesaplar-arası ayrım yapamaz — bkz. dosya sonundaki epoch-guard extension'ı).
    private var accountEpoch = 0

    private let entitlementBroadcast = AsyncMulticast<EntitlementSnapshot>()
    let balanceBroadcast = AsyncMulticast<CoinBalance>() // versiyonsuz (UI/ProfileKit)
    let versionedBalanceBroadcast = AsyncMulticast<VersionedCoinBalance>() // versiyonlu ikiz (RewardsKit başlık)

    public init(
        remote: any WalletRemoting,
        analytics: any AnalyticsTracking,
        log: any Logging,
        now: @escaping @Sendable () -> Date = { Date() },
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString },
        earnVelocityRecorder: (any EarnVelocityRecording)? = nil
    ) {
        self.remote = remote
        self.analytics = analytics
        self.log = log
        self.now = now
        self.makeIdempotencyKey = makeIdempotencyKey
        self.earnVelocityRecorder = earnVelocityRecorder
        subscription = .none
        snapshot = Self.initialSnapshot(now: now)
    }

    /// Boş/başlangıç cüzdan snapshot'ı (init + `reset` tek kaynaktan üretir — drift yok).
    private static func initialSnapshot(now: () -> Date) -> WalletSnapshot {
        WalletSnapshot(
            balance: .zero,
            earnedExpiringSoon: nil,
            firstTopUpEligible: false,
            updatedAt: now(),
            version: Int.min
        )
    }

    // MARK: - Hesap-değişimi (§575)

    /// Hesap-değişiminde (SS-132/§575) yerel cüzdan state'ini SIFIRLAR — önceki hesabın bakiye/abonelik/
    /// açılmış-bölüm state'i yeni hesaba SIZMAZ. Version + subscription guard'ları da sıfırlanır (ilk
    /// `refresh()` düşük-version snapshot'ı TAZE uygular). `accountEpoch` artışı uçuştaki yanıtları fence eder.
    public func reset() {
        accountEpoch &+= 1 // uçuştaki önceki-hesap yanıtlarını fence et (audit HIGH)
        snapshot = Self.initialSnapshot(now: now)
        hasServerSnapshot = false
        subscription = .none
        hasServerSubscription = false
        storeKitOptimisticVIP = false
        unlockedEpisodes = []
        pendingUnlock = nil
        broadcastBalance(from: snapshot)
        broadcastEntitlement()
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

    /// PlayerKit ön-kontrolü (04 §9.1): VIP tümü açar; değilse daha önce açılmış mı. Yetkinin doğruluk
    /// kaynağı yine sunucudur (`POST /playback/authorize`).
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

    /// `GET /wallet` + `GET /subscription` — otoritatif tazeleme (06 §4.5). Epoch fetch await'inden ÖNCE
    /// yakalanır; hesap araya değiştiyse (reset) uçuştaki önceki-hesap yanıtı apply edilMEZ (§575).
    public func refresh() async {
        let epoch = accountEpoch
        do {
            let wallet = try await remote.fetchWallet()
            guard epoch == accountEpoch else {
                log.debug("wallet refresh dropped: account epoch changed mid-flight")
                return
            }
            applyWallet(wallet)
        } catch {
            log.error("wallet refresh failed: \(String(describing: error))")
        }
        do {
            let subscription = try await remote.fetchSubscription()
            guard epoch == accountEpoch else {
                log.debug("subscription refresh dropped: account epoch changed mid-flight")
                return
            }
            applySubscription(subscription)
        } catch {
            log.error("subscription refresh failed: \(String(describing: error))")
        }
    }

    /// StoreKit `currentEntitlements`'tan iyimser VIP tohumlar (06 §4.5): yalnız sunucu aboneliği henüz
    /// gelmemişken. Sunucu snapshot'ı geldiğinde ezilir; uyuşmazlık loglanır.
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

    /// İyimser kilit açma — iyimserlik BAKİYEDE DEĞİL, UNLOCK DURUMUNDA (kanon §5; 05 §5.2; 06 §2.4 kural 3:
    /// istemci bakiyeyi ASLA lokal aritmetikle güncellemez). Akış: (a) bölümü hemen açık işaretle (entitlement),
    /// (b) bakiye YALNIZ sunucu snapshot'ından SET edilir (lokal çıkarma/yayın YOK), (c) server reddinde
    /// (INSUFFICIENT_COINS/PRICE_CHANGED) iyimser kilit geri alınır + tipli sonuç döner. Aynı anda en fazla 1
    /// bekleyen unlock (06 §6.4) — ikincisi `transactionConflict` döner.
    public func unlock(episodeID: EpisodeID, expectedPrice: Int) async -> UnlockResult {
        guard pendingUnlock == nil else {
            return .failed(.wallet(.transactionConflict))
        }
        pendingUnlock = episodeID
        // Yalnız KENDİ marker'ımızı temizle: uçuştayken reset() + araya giren unlock (aktör-reentrancy)
        // pendingUnlock'u BAŞKA bölüme taşıyabilir → silme (≤1 bekleyen unlock, 06 §6.4).
        defer {
            if pendingUnlock == episodeID {
                pendingUnlock = nil
            }
        }

        // (a) İyimser entitlement: bölümü açık işaretle (hasAccess açılır → PlayerKit ön-kontrolü geçer). Bakiyeye
        // DOKUNULMAZ, yayınlanmaz. `lastUnlocked` YAYINLANMAZ (ONAYLANMIŞ-unlock sinyali → UnlockSheet kapanır);
        // iyimser yayın onu taşırsa sheet server reddinden önce kapanıp red-işleme ölü-kod olur (audit HIGH).
        let wasUnlocked = unlockedEpisodes.contains(episodeID)
        if !wasUnlocked {
            optimisticallyMarkUnlocked(episodeID)
        }

        let key = makeIdempotencyKey()
        let epoch = accountEpoch // await'ten ÖNCE yakala (§575 audit HIGH)
        do {
            let outcome = try await remote.unlock(
                episodeID: episodeID,
                expectedPrice: expectedPrice,
                idempotencyKey: key
            )
            // Hesap araya değiştiyse (reset epoch'u artırdı) bu yanıt ÖNCEKİ hesaba aittir → uygulama
            // (applyWallet + confirmUnlocked) X'in bakiyesini/kilidini Y'ye sızdırır → DÜŞÜR.
            guard epoch == accountEpoch else {
                log.debug("unlock response dropped: account epoch changed mid-flight")
                return .failed(.wallet(.transactionConflict))
            }
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
        case let .unlocked(record, wallet, transactions):
            // (b) Server-otoritatif snapshot bakiyeyi SET eder (lokal çıkarma YOK); kilit kalıcı.
            applyWallet(wallet)
            confirmUnlocked(record.episodeID)
            // Kanonik ödeme funnel success adımı (08 §3.4/§5.2 `unlock_coin`): cüzdan düşümü
            // backend'de onaylandığında (idempotent işlem tamam) atılır. Funnel event'i YALNIZ
            // burada (backend onay noktası) atılır; UI kendi funnel event'ini atmaz (çift-atım yok).
            trackUnlockCoin(record: record, wallet: wallet, transactions: transactions)
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
        recordEarnVelocity(from: snapshot, to: incoming)
        snapshot = incoming
        hasServerSnapshot = true
        broadcastBalance(from: incoming)
    }

    /// Kazanç-hızı gözlemi (SS-100): iki SERVER snapshot arası earned-kese ARTIŞI bir kazanç
    /// olayıdır (check-in/görev/rewarded-ad/vip-bonus kredisi). Danışma monitörüne raporlanır.
    /// - İLK server snapshot'ında baseline YOK → kaydedilmez (hasServerSnapshot henüz false).
    /// - Earned DÜŞÜŞÜ (unlock harcaması / iade) ve purchased-kese değişimi kazanç DEĞİLDİR.
    /// Yalnız gözlem: bakiyeyi/versiyonu/kontrol akışını ETKİLEMEZ; recorder yoksa no-op.
    private func recordEarnVelocity(from previous: WalletSnapshot, to incoming: WalletSnapshot) {
        guard hasServerSnapshot, let earnVelocityRecorder else { return }
        let earnedDelta = incoming.balance.earnedCoins - previous.balance.earnedCoins
        guard earnedDelta > 0 else { return }
        earnVelocityRecorder.recordEarn(coins: earnedDelta)
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

    /// `unlock_coin` (08 §3.4 satır 201 zorunlu şeması): `earned_spent`/`purchased_spent` sunucunun kese-bazlı
    /// ledger satırlarından (05 §2.6) türetilir, `balance_after` server snapshot'ından, `unlock_price` kaydın
    /// harcanan coin'i. İdempotent re-unlock'ta ledger satırı gelmezse harcamalar 0 raporlanır.
    private func trackUnlockCoin(record: UnlockRecord, wallet: WalletSnapshot, transactions: [CoinTransaction]) {
        analytics.track(
            "unlock_coin",
            parameters: [
                "series_id": .string(record.seriesID.rawValue),
                "episode_id": .string(record.episodeID.rawValue),
                "unlock_price": .int(record.coinsSpent),
                "earned_spent": .int(spentInBucket(.earned, transactions)),
                "purchased_spent": .int(spentInBucket(.purchased, transactions)),
                "balance_after": .int(wallet.balance.totalCoins)
            ]
        )
    }

    /// Bir kesede bu unlock için harcanan (pozitif) coin: episodeUnlock tipli, negatif (harcama)
    /// ledger satırlarının mutlak toplamı.
    private func spentInBucket(_ bucket: CoinTransaction.Bucket, _ transactions: [CoinTransaction]) -> Int {
        transactions
            .filter { $0.type == .episodeUnlock && $0.bucket == bucket && $0.amount < 0 }
            .reduce(0) { $0 - $1.amount }
    }

    /// İYİMSER kilit (server ONAYI ÖNCESİ): `hasAccess`'i açar + entitlement yayınlar ama `lastUnlocked`
    /// YAYMAZ. `lastUnlocked` "onaylanmış unlock" (sheet kapanır) sinyali olduğundan iyimser yayında
    /// taşınmaz — aksi halde UnlockSheet server reddinden önce kapanır (audit HIGH; red-işleme ölü-kod).
    private func optimisticallyMarkUnlocked(_ episodeID: EpisodeID) {
        let (inserted, _) = unlockedEpisodes.insert(episodeID)
        if inserted {
            broadcastEntitlement()
        }
    }

    /// ONAYLANMIŞ kilit (server success): sette olduğundan emin olur ve `lastUnlocked` YAYAR — UnlockSheet
    /// gözlemcisi bununla `completeUnlock` eder. İyimser adım zaten eklemişse insert no-op'tur; yayın yine
    /// yapılır (onay sinyali). İlk kez açılıyorsa (idempotent re-unlock / wasUnlocked) da doğru çalışır.
    private func confirmUnlocked(_ episodeID: EpisodeID) {
        unlockedEpisodes.insert(episodeID)
        broadcastEntitlement(lastUnlocked: episodeID)
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

// MARK: - Snapshot uygulama + hesap-epoch guard'ı (§575 audit HIGH)

/// `apply(...)` GÜNCEL epoch'ta uygular (test seed'i + await-geçmeyen çağrılar). Cross-actor krediciler
/// (PurchaseCoordinator) server await'ini AŞTIĞINDA `currentEpoch()`'u await ÖNCESİ okur ve
/// `applyIfCurrentEpoch(...:epoch:)`e geçer; hesap araya değiştiyse kredi ÖNCEKİ hesaba aittir → düşürülür
/// (TOCTOU yok; kontrol+apply tek actor-hop). unlock()/refresh() epoch'u kendi içinde yakalar.
public extension WalletStore {
    func apply(walletSnapshot incoming: WalletSnapshot) {
        applyWallet(incoming)
    }

    func apply(subscription incoming: SubscriptionStatus) {
        applySubscription(incoming)
    }

    func currentEpoch() -> Int {
        accountEpoch
    }

    func applyIfCurrentEpoch(walletSnapshot incoming: WalletSnapshot, epoch: Int) {
        guard epoch == accountEpoch else {
            log.debug("wallet credit dropped: account epoch changed mid-flight")
            return
        }
        applyWallet(incoming)
    }

    func applyIfCurrentEpoch(subscription incoming: SubscriptionStatus, epoch: Int) {
        guard epoch == accountEpoch else {
            log.debug("subscription update dropped: account epoch changed mid-flight")
            return
        }
        applySubscription(incoming)
    }

    /// Subscription monotonluk guard'ı (applyWallet ile simetri): HEM mevcut HEM gelen `updatedAt` varsa daha
    /// ESKİ snapshot bayattır (uçuştaki non-VIP fetch taze VIP'i ezmesin); `updatedAt` nil ise son-yazan-kazanır.
    private func isStaleSubscription(_ incoming: SubscriptionStatus) -> Bool {
        guard hasServerSubscription,
              let incomingAt = incoming.updatedAt,
              let currentAt = subscription.updatedAt
        else { return false }
        return incomingAt < currentAt
    }
}
