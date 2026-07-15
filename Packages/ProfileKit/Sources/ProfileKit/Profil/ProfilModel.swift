import AppFoundation
import Observation

/// `Profil` ekran modeli (SS-130). @Observable/@MainActor; SwiftUI View ince kalır. Hesap özeti
/// (misafir/bağlı — `SessionManaging`'den), coin bakiyesi + VIP durumu (`WalletSummaryReading`
/// portundan), izleme geçmişi/Ayarlar/CoinMagazasi girişleri (delegate niyetleri). WalletKit/
/// LibraryKit import EDİLMEZ — cross-feature veri porttan, navigasyon delegate'ten (R2/R8).
@MainActor
@Observable
public final class ProfilModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .loading
    public private(set) var account: AccountSummary = .init(kind: .guest)
    public private(set) var wallet: WalletSummary = .empty
    /// Uygulama sürümü (alt bölge; App CFBundleShortVersionString geçirir).
    public let appVersion: String
    /// BildirimMerkezi satırı görünür mü (Faz 2 flag; 02 §4.13).
    public let notificationCenterEnabled: Bool

    // MARK: - Bağımlılıklar

    private let session: any SessionManaging
    private let walletSummary: any WalletSummaryReading
    private let analytics: any AnalyticsTracking
    private let appLanguageProvider: (any AppLanguageProviding)?
    private weak var delegate: (any ProfileDelegate)?

    private var loadTask: Task<Void, Never>?

    /// Seçili uygulama dili (SS-161) — VIP yenileme tarihi buna göre yerelleşir (review #13).
    /// Bağlanmadıysa kanonik varsayılana (`.default`) düşer.
    public var appLanguage: AppLanguage {
        appLanguageProvider?.appLanguage ?? .default
    }

    public init(
        session: any SessionManaging,
        walletSummary: any WalletSummaryReading,
        analytics: any AnalyticsTracking,
        delegate: (any ProfileDelegate)?,
        appLanguage appLanguageProvider: (any AppLanguageProviding)? = nil,
        appVersion: String = "",
        notificationCenterEnabled: Bool = false
    ) {
        self.session = session
        self.walletSummary = walletSummary
        self.analytics = analytics
        self.appLanguageProvider = appLanguageProvider
        self.delegate = delegate
        self.appVersion = appVersion
        self.notificationCenterEnabled = notificationCenterEnabled
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        trackScreenView()
        startLoadIfNeeded()
    }

    /// İlk yükleme görevini yalnız BİR kez başlatır (onAppear veya observeUpdates hangisi önce
    /// gelirse). Tek görev referansı, load ↔ observeUpdates sıralama koordinasyonunu mümkün kılar.
    private func startLoadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// Testler için: askıdaki ilk yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    /// İlk yükleme: oturum durumundan hesap özeti + cüzdan portundan bakiye/VIP (cache-first).
    public func load() async {
        let state = await session.state
        account = AccountSummary.make(from: state)
        wallet = await walletSummary.currentSummary()
        loadState = .loaded
    }

    /// Canlı akışları dinler (cüzdan + oturum). View `.task` ile sürer → ekran kaybolunca OTOMATİK
    /// iptal (Task leaki yok). Cüzdan: başka cihazdan satın alma/VIP; oturum: bağlama sonrası
    /// misafir→bağlı geçişi Profil açıkken yansır.
    public func observeUpdates() async {
        // İlk yükleme (snapshot) ile canlı akışları SIRALA: load() önce çalışıp cache-first snapshot'ı
        // yazsın, ARDINDAN canlı akışların replay'i (her zaman ≥ snapshot tazeliğinde) SON söz sahibi
        // olsun. Aksi halde load()'ın ayrı currentSummary()/state okuması, replay'in daha taze
        // değerini clobber edebilir (review #12). onAppear ile .task sırasından bağımsız güvenli.
        startLoadIfNeeded()
        await loadTask?.value
        async let walletStream: Void = observeWallet()
        async let sessionStream: Void = observeSession()
        _ = await (walletStream, sessionStream)
    }

    private func observeWallet() async {
        for await summary in walletSummary.summaryUpdates() {
            wallet = summary
        }
    }

    private func observeSession() async {
        for await state in session.stateUpdates {
            account = AccountSummary.make(from: state)
        }
    }

    // MARK: - Navigasyon niyetleri (delegate → App)

    /// Misafir "Hesabını bağla" CTA / oturum düştüyse yeniden giriş (02 §4.13).
    public func linkOrReauthenticate() {
        switch account.kind {
        case let .sessionExpired(provider):
            delegate?.profileRequestsReauthentication(provider: provider)
        case .guest, .linked:
            trackRow("link_account")
            delegate?.profileRequestsAccountLinking()
        }
    }

    public func openCoinStore() {
        trackRow("coins")
        delegate?.profileOpensCoinStore()
    }

    public func openVIP() {
        trackRow("vip")
        delegate?.profileOpensVIP(isSubscribed: wallet.isVIP)
    }

    public func openWatchHistory() {
        trackRow("watch_history")
        delegate?.profileOpensWatchHistory()
    }

    public func openSettings() {
        trackRow("settings")
        delegate?.profileOpensSettings()
    }

    public func openNotificationCenter() {
        trackRow("notifications")
        delegate?.profileOpensNotificationCenter()
    }

    public func openSupport() {
        trackRow("support")
        delegate?.profileOpensSupport()
    }

    // MARK: - İç (analitik, 02 §4.13)

    private func trackScreenView() {
        analytics.track("screen_view", parameters: ["screen_name": .string("profil")])
    }

    private func trackRow(_ row: String) {
        analytics.track("profile_row_tapped", parameters: ["row": .string(row)])
    }
}
