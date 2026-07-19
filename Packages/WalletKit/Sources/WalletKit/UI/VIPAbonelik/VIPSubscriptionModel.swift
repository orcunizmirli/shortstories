import AppFoundation
import Foundation
import Observation

/// VIPAbonelik giriş kaynağı (08 §3.4 `subscription_view.source`).
public enum VIPSource: String, Sendable, Equatable {
    case unlockSheet = "unlock_sheet"
    case profil
    case onboarding
    case deeplink
}

/// Ekran modu (06 §8.2/§8.3): abone değilse plan satışı, aboneyse yönetim görünümü.
public enum VIPScreenMode: Equatable, Sendable {
    case purchase
    case management
}

/// VIPAbonelik intent sözleşmesi — App koordinatörü bağlar (06 §8.3 yönetim yönlendirmesi).
@MainActor
public protocol VIPSubscriptionDelegate: AnyObject {
    /// Abonelik aktifleşti → açık sheet yığını kapanır, bağlama dönülür (kilitli bölümden
    /// gelindiyse video başlar, 06 §8 / 02 §4.8).
    func vipSubscriptionDidActivate()
    /// "Aboneliği Yönet" → App `showManageSubscriptions(in:)` sunar; başarısızsa iOS abonelik
    /// ayarları deep link'i (06 §8.3). Uygulama içinde ayrı iptal akışı YOK.
    func vipSubscriptionRequestsManagement()
    /// Kullanıcı ekranı kapattı.
    func vipSubscriptionRequestsDismiss()
}

/// VIPAbonelik ekran modeli (SS-096). @Observable/@MainActor. Plan karşılaştırma, intro offer
/// gösterimi (StoreKit'ten; uygun kullanıcıya), abonelik satın alma durum makinesi ve iptal/iade
/// sonrası entitlement düşürme yansıması (canlı entitlement yayınından).
@MainActor
@Observable
public final class VIPSubscriptionModel {
    // MARK: - Durum (Observable)

    public private(set) var loadPhase: ShopLoadPhase = .loading
    public private(set) var plans: [VIPPlanOption] = []
    public private(set) var selectedPlan: SubscriptionPlan = .yearly
    public private(set) var subscription: SubscriptionStatus = .none
    public private(set) var purchasePhase: StorePurchasePhase = .idle

    /// Abone değilse plan satışı; aboneyse yönetim (06 §8.2/§8.3).
    public var mode: VIPScreenMode {
        subscription.isVIP ? .management : .purchase
    }

    /// Grace/billing-retry banner'ı (06 §8.4): "Ödeme yöntemini güncelle".
    public var showsPaymentIssueBanner: Bool {
        subscription.isVIP && subscription.isInGracePeriod
    }

    /// Seçili planın birleşik kalemi (fiyat + intro).
    public var selectedOption: VIPPlanOption? {
        plans.first { $0.plan == selectedPlan }
    }

    // MARK: - Win-back yüzeyi (SS-099 F2)

    /// Win-back banner'ın görünürlük + mesaj KARARI. İstemci karar VERMEZ; server-otoriter türev
    /// (`WinBackEligibility` sunucu sinyalini ezmeye izin vermez) + App-enjekte remote-config/varyant/
    /// frekans kapılarından geçer (`WinBackSurface.resolve`). View bunu okur; `subscription`/`plans`
    /// gözlenebilir olduğundan entitlement düşünce/plan yüklenince banner reaktif güncellenir.
    public var winBackSurface: WinBackSurface {
        let now = winBack.now()
        let eligibility = WinBackEligibility.evaluate(
            subscription: subscription,
            serverSignal: winBack.serverSignal,
            now: now,
            formerVIPGraceDays: winBack.formerVIPGraceDays,
            nearExpiryWindow: winBack.nearExpiryWindow
        )
        return WinBackSurface.resolve(
            eligibility: eligibility,
            remoteConfigEnabled: winBack.isRemoteConfigEnabled,
            variant: winBack.variant,
            frequency: winBack.frequency,
            policy: winBack.policy,
            offer: winBackOffer,
            expiryDateText: subscription.expiresAt.map(winBack.expiryDateFormatter),
            now: now
        )
    }

    /// Win-back offer'ı GRACEFUL çözer (06 §8.2 uygun olmayana gösterme): auto-renew kapalı VIP'te
    /// kullanıcının mevcut planına ait üründen, eski VIP'te seçili (varsayılan yıllık) üründen okur —
    /// canlı katman doldurmadıysa `nil`. Fiyat StoreKit `displayPrice`'tan; hardcode YASAK.
    private var winBackOffer: WinBackOffer? {
        guard let product = winBackOfferOption?.product else { return nil }
        return WinBackOffer.resolve(from: product)
    }

    /// Offer'ın okunacağı plan: hâlâ VIP'sek mevcut plana ait ürün (`SubscriptionStatus.Plan` ile
    /// `SubscriptionPlan` aynı raw değerlerle eşlenir), aksi halde seçili plan (varsayılan yıllık).
    private var winBackOfferOption: VIPPlanOption? {
        if let plan = subscription.plan, let match = plans.first(where: { $0.plan.rawValue == plan.rawValue }) {
            return match
        }
        return selectedOption
    }

    // MARK: - Win-back §11.4 açıklaması + tek-kaynak tarih (SS-099 F1/F2)

    /// Fiyatlı win-back CTA'sına BİTİŞİK §11.4 açıklaması (offer fiyatı + dönemi + offer-sonrası
    /// normal fiyat/dönem). Surface fiyat gösteriyorsa (`.discount` + offer) VE normal fiyat/dönem
    /// TAM ise dolu; eksikse `nil` → fiyatlı CTA gösterilmez (compliance > gösterim; fiyat StoreKit'ten).
    public var winBackRenewalDisclosure: WinBackRenewalDisclosure? {
        guard winBackSurface.offerDisplayPrice != nil else { return nil }
        return WinBackRenewalDisclosure.resolve(from: winBackOfferOption)
    }

    /// View kararı (F1): `true` iken banner CTA'sının altına §11.4 açıklaması çizilir — HER modda
    /// (purchase + management). App Store Guideline 3.1.2: fiyatlı satın-alma CTA'sına bitişik açıklama.
    public var winBackRequiresRenewalDisclosure: Bool {
        winBackRenewalDisclosure != nil
    }

    /// Banner CTA fiyatı — YALNIZ §11.4 açıklaması TAM iken; aksi halde `nil` → nötr "geri dön"
    /// (açıklamasız fiyatlı satın-alma CTA'sı çizilmez).
    public var winBackBannerOfferPrice: String? {
        winBackRenewalDisclosure?.offerPrice
    }

    /// View kararı (F2): autoRenewOff win-back banner'ı bitiş cümlesini gösterirken managementSection'ın
    /// ayrı yenileme-tarihi satırı BASTIRILIR (tek kaynak; çift + format-tutarsız tarih gösterimi önlenir).
    public var showsManagementRenewalText: Bool {
        !(winBackSurface.isVisible && winBackSurface.reason == .autoRenewOff)
    }

    // MARK: - Bağımlılıklar

    private let source: VIPSource
    private let loader: any StorefrontLoading
    private let wallet: any WalletGateway
    private let purchasing: any WalletPurchasing
    private let analytics: any AnalyticsTracking
    /// Win-back seam (SS-099 F2): App remote-config kill-switch + SS-154 varyant + segment sinyali +
    /// frekans durumu + tarih biçimleyiciyi enjekte eder. Varsayılan `.disabled` → banner yok.
    private let winBack: WinBackConfiguration
    private weak var delegate: (any VIPSubscriptionDelegate)?

    private var observationTask: Task<Void, Never>?
    private var started = false
    /// Sheet kapandı — `begin()` await'te askıdayken `onDisappear` gelirse gözlem görevinin await
    /// SONRASI kurulup asla iptal edilmemesini (kalıcı sızıntı) engeller.
    private var isDisposed = false
    /// Aktivasyon delegate'i bu ekran ömründe atıldı mı (idempotent). Zaten VIP açılan yönetim
    /// modunda `true` tohumlanır → canlı akışın replay'i sahte "aktifleşti" tetiklemez.
    private var didFireActivation = false
    /// Win-back banner'ı bu ekran ömründe App'e "gösterildi" olarak bir kez bildirdik mi (idempotent
    /// frekans persist tetikleyicisi; yüzey saf kalır, sayacı App artırır).
    private var didNotifyWinBack = false

    public init(
        source: VIPSource,
        loader: any StorefrontLoading,
        wallet: any WalletGateway,
        purchasing: any WalletPurchasing,
        analytics: any AnalyticsTracking,
        winBack: WinBackConfiguration = .disabled,
        delegate: (any VIPSubscriptionDelegate)?
    ) {
        self.source = source
        self.loader = loader
        self.wallet = wallet
        self.purchasing = purchasing
        self.analytics = analytics
        self.winBack = winBack
        self.delegate = delegate
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        Task { await begin() }
    }

    public func onDisappear() {
        isDisposed = true
        observationTask?.cancel()
        observationTask = nil
    }

    /// Abonelik durumu seed + `subscription_view` analitiği + canlı entitlement gözlemi (iptal/
    /// iade/expiry yansıması) + plan yükleme. Testler doğrudan `await` eder.
    func begin() async {
        guard !started else { return }
        started = true
        subscription = await wallet.subscriptionStatus()
        // Zaten VIP açılan yönetim modunda aktivasyonu "tüketilmiş" say → canlı akış replay'i sahte
        // didActivate tetiklemez (sheet yalnız BU ekran ömründe VIP olunca kapanmalı).
        didFireActivation = subscription.isVIP
        // Await sırasında sheet kapandıysa gözlem kurma (kalıcı sızıntı olmasın).
        guard !isDisposed else { return }
        analytics.track("subscription_view", parameters: ["source": .string(source.rawValue)])
        startObserving()
        await load()
    }

    private func startObserving() {
        guard !isDisposed, observationTask == nil else { return }
        // Akış görev DIŞINDA yakalanır; görev `self`'i yalnız ZAYIF tutar (retain-cycle yok).
        let updates = wallet.entitlementUpdates()
        observationTask = Task { [weak self] in
            for await _ in updates {
                guard let self else { break }
                await handleEntitlementChange()
            }
        }
    }

    /// Entitlement değişimi (başlangıç/expiry/grace/iade) → durumu otoritatif tazele; mode buna göre
    /// purchase↔management geçer (06 §8.4). VIP BU ekran ömründe aktifleşirse — satın alma StoreKit
    /// sonucundan bağımsız (ör. başka cihaz/family/pending Ask-to-Buy onayı) — aktivasyon delegate'i
    /// idempotent atılır (sheet yığını kapanır, kilitli bölüm oynar; 06 §6.6 / §8).
    private func handleEntitlementChange() async {
        subscription = await wallet.subscriptionStatus()
        if subscription.isVIP {
            fireActivationIfNeeded()
        }
    }

    /// Aktivasyon delegate'ini ekran ömründe EN FAZLA BİR KEZ atar (subscribe .completed VE canlı
    /// gözlem aynı aktivasyonu görebilir → çift çağrı yok).
    private func fireActivationIfNeeded() {
        guard !didFireActivation else { return }
        didFireActivation = true
        delegate?.vipSubscriptionDidActivate()
    }

    // MARK: - Yükleme

    public func load() async {
        loadPhase = .loading
        do {
            let products = try await loader.loadProducts(ids: ShortSeriesProduct.subscriptions)
            let merged = StorefrontMerge.vipPlans(products: products).sorted { $0.plan.displayOrder < $1.plan.displayOrder }
            plans = merged
            selectedPlan = defaultSelection(from: merged)
            loadPhase = merged.isEmpty ? .failed : .loaded
        } catch {
            loadPhase = .failed
        }
    }

    public func retry() async {
        await load()
    }

    private func defaultSelection(from plans: [VIPPlanOption]) -> SubscriptionPlan {
        // Varsayılan yıllık (06 §8.1 "en avantajlı"); yoksa mevcut ilk plan.
        if plans.contains(where: { $0.plan == .yearly }) {
            return .yearly
        }
        return plans.first?.plan ?? .yearly
    }

    // MARK: - Seçim + satın alma

    public func select(_ plan: SubscriptionPlan) {
        guard plans.contains(where: { $0.plan == plan }) else { return }
        selectedPlan = plan
    }

    public func subscribe() async {
        // Çift satın alma koruması: uçuşta VEYA Ask-to-Buy onayı beklerken (pending) yeni istek yok.
        guard !purchasePhase.preventsNewPurchase, let option = selectedOption else { return }
        purchasePhase = .purchasing(productID: option.product.id)
        trackSubscriptionStart(option)

        let result = await purchasing.purchase(productID: option.product.id)
        purchasePhase = StorePurchasePhase.resolve(result, productID: option.product.id)

        switch result {
        case let .completed(transactionID):
            subscription = await wallet.subscriptionStatus()
            trackSubscriptionSuccess(option, transactionID: transactionID)
            fireActivationIfNeeded()
        case .cancelled:
            break // sessiz (06 §7.5)
        case let .failed(error):
            trackSubscriptionFail(option, error: error, stage: "storekit")
        case .invalidReceipt:
            trackSubscriptionFail(option, error: .wallet(.receiptInvalid), stage: "verification")
        case .pending, .verificationPending:
            break
        }
    }

    /// Win-back banner CTA'sı (SS-099 F2): offer'ın ait olduğu plana geçip mevcut VIP satın-alma
    /// akışına bağlanır — coin/entitlement mutasyonu YOK, karar `subscribe()` durum makinesine düşer.
    /// TODO(SS-099): StoreKit 2 win-back offer purchase özel imza ister (`Product.PurchaseOption`
    ///   win-back offer imza/nonce). Canlı katman offer'ı bağladığında `purchasing.purchase` bu
    ///   parametreyi taşıyacak; şimdilik standart abonelik satın alma akışına (graceful) bağlanır.
    public func subscribeViaWinBack() {
        if let option = winBackOfferOption {
            select(option.plan)
        }
        Task { await subscribe() }
    }

    /// Win-back banner bu ekran ömründe İLK kez göründüğünde App'e bildirir (frekans sayacını App
    /// persist eder; 07 §5.3). İdempotent — banner yeniden çizilse de bir kez tetikler. View banner'ın
    /// `.onAppear`'ında çağırır.
    public func winBackBannerAppeared() {
        guard !didNotifyWinBack else { return }
        let surface = winBackSurface
        guard surface.isVisible, let variant = surface.variant, let reason = surface.reason else { return }
        didNotifyWinBack = true
        winBack.onBannerShown?(variant, reason)
    }

    /// "Aboneliği Yönet" (06 §8.3): iptal/plan değişimi Apple UI'ıyla; uygulama içinde ayrı akış yok.
    public func manageSubscription() {
        // 08 §3.4: `product_id` zorunlu — bilinmeyen/eksik planda bile parametre düşürülmez
        // (aksi halde funnel'da atıfsız event oluşurdu).
        analytics.track(
            "subscription_cancel_intent",
            parameters: ["product_id": .string(cancelIntentProductID())]
        )
        delegate?.vipSubscriptionRequestsManagement()
    }

    private func cancelIntentProductID() -> String {
        switch subscription.plan {
        case .weekly: "vip_weekly"
        case .monthly: "vip_monthly"
        case .yearly: "vip_yearly"
        case .unknown, .none: "vip_unknown"
        }
    }

    /// "Satın Alımları Geri Yükle" (App Store Review zorunlu, 06 §11.3).
    public func restore() async {
        analytics.track("restore_tapped", parameters: ["source": .string(source.rawValue)])
        try? await purchasing.restore()
    }

    public func acknowledgeTransientPhase() {
        switch purchasePhase {
        case .success, .failed, .invalidReceipt, .pending, .verificationPending:
            purchasePhase = .idle
        case .idle, .purchasing:
            break
        }
    }

    public func dismiss() {
        delegate?.vipSubscriptionRequestsDismiss()
    }

    // MARK: - Analitik

    private func trackSubscriptionStart(_ option: VIPPlanOption) {
        analytics.track(
            "subscription_start",
            parameters: [
                "product_id": .string(option.plan.analyticsID),
                "price_usd": .double(option.product.price.doubleValue),
                "has_intro_offer": .bool(option.showsIntroOffer)
            ]
        )
    }

    private func trackSubscriptionSuccess(_ option: VIPPlanOption, transactionID: String) {
        // 08 §3.4 satır 206: `transaction_id` zorunlu (App Store işlemine join / iade-dedupe).
        analytics.track(
            "subscription_success",
            parameters: [
                "product_id": .string(option.plan.analyticsID),
                "price_usd": .double(option.product.price.doubleValue),
                "is_intro": .bool(option.showsIntroOffer),
                "transaction_id": .string(transactionID)
            ]
        )
    }

    private func trackSubscriptionFail(_ option: VIPPlanOption, error: AppError, stage: String) {
        let (domain, code) = AnalyticsMapping.domainCode(error)
        analytics.track(
            "subscription_fail",
            parameters: [
                "product_id": .string(option.plan.analyticsID),
                "error_domain": .string(domain),
                "error_code": .string(code),
                "stage": .string(stage)
            ]
        )
    }
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
