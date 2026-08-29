import AppFoundation
import Observation

/// Davet-arkadaş (referral) ekran modeli (RWD-07 — client soyutlama). @Observable/@MainActor; View ince.
/// Davet kodu/sayaç durumu (`ReferralGateway.status`), paylaşım niyeti (delegate → App), kod kullanma
/// (redeem — SERVER-OTORİTER).
///
/// PARA GÜVENLİĞİ (06 §, R6): redeem SERVER-OTORİTER. İstemci OPTİMİSTİK KREDİ VERMEZ — başarı yalnız
/// server 200'ünde (`ReferralRedeemOutcome.credited`) `redeemState=.credited`e geçer. İş-kuralı
/// çakışmaları (geçersiz kod / kendine-davet) kullanıcıya GÖSTERİLİR (check-in 409'unun aksine sessiz
/// DEĞİL). Transport hatası → kredi/başarı YOK, retry. Coin BAKİYESİ bu ekranda gösterilmez
/// (OdulMerkezi'nin işi — davet ekranı oradan açılır); kazanılan ödül `redeemState.credited(coins:)`.
@MainActor
@Observable
public final class ReferralModel {
    /// Ekranın yükleme durumu (DSStateView sözleşmesi, 02 §3).
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case failed
        case offline
    }

    /// Redeem transport başarısızlığı (transient; kredi VERİLMEZ).
    public enum RedeemFailure: Equatable, Sendable {
        case offline
        case generic
    }

    /// Redeem akış durumu — View bunu switch'ler.
    public enum RedeemState: Equatable, Sendable {
        case idle
        case redeeming
        /// Başarı (kutlama) — kazanılan coin (server onayı).
        case credited(coins: Int)
        /// Kullanıcıya-görünür iş-kuralı çakışması (kredi yok).
        case conflict(ReferralConflict)
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .loading
    public private(set) var status: ReferralStatus?
    public private(set) var redeemState: RedeemState = .idle
    /// Son redeem denemesinin transport hatası; başarıda/yeni denemede/yeni yüklemede sıfırlanır.
    public private(set) var redeemFailure: RedeemFailure?
    /// Başarılı redeem sayacı — View haptic/animasyonu bu token'la tetikler (server onayı SONRASI).
    public private(set) var redeemCelebration = 0

    // MARK: - Türetimler (SAF; View doğrudan okur)

    public var inviteCode: String {
        status?.inviteCode ?? ""
    }

    public var invitedCount: Int {
        status?.invitedCount ?? 0
    }

    public var rewardPerReferral: Int {
        status?.rewardPerReferral ?? 0
    }

    public var canRedeem: Bool {
        loadState == .loaded && status?.canRedeem == true
    }

    public var shareEnabled: Bool {
        loadState == .loaded && !(status?.inviteCode.isEmpty ?? true)
    }

    // MARK: - Bağımlılıklar

    private let gateway: any ReferralGateway
    private let analytics: any AnalyticsTracking
    private weak var delegate: (any ReferralDelegate)?

    public init(
        gateway: any ReferralGateway,
        analytics: any AnalyticsTracking,
        delegate: (any ReferralDelegate)?
    ) {
        self.gateway = gateway
        self.analytics = analytics
        self.delegate = delegate
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        Task { await load() }
    }

    /// Davet durumunu yükler. Her (yeniden) görünmede çağrılır → server durumunu tazeler VE bayat redeem
    /// geri bildirimini temizler (model koordinatörde retained, View @State değil → stale çakışma/başarı
    /// mesajı yeniden açılışta kalmasın). Durum hatası birincil yüzeyi (ekranı) belirler.
    public func load() async {
        redeemState = .idle
        redeemFailure = nil
        do {
            let state = try await gateway.status()
            status = state
            loadState = .loaded
            analytics.trackReferralView(invitedCount: state.invitedCount, canRedeem: state.canRedeem)
        } catch {
            loadState = Self.loadFailure(for: error)
        }
    }

    /// Hata durumundan "Tekrar Dene".
    public func retry() async {
        loadState = .loading
        await load()
    }

    /// Davet paylaş niyeti → delegate → App paylaşım sayfası. Server URL'i varsa geçirir (istemci kurmaz).
    public func shareInvite() {
        guard let state = status, !state.inviteCode.isEmpty else { return }
        analytics.trackReferralShared()
        delegate?.referralSharesInvite(code: state.inviteCode, url: state.inviteURL)
    }

    /// Davet kodu kullan — SERVER-OTORİTER + idempotent. Guard: yüklenmiş, uygun, boşta değil, kod dolu.
    public func redeem(_ rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loadState == .loaded, canRedeem, redeemState != .redeeming, !code.isEmpty else { return }
        redeemState = .redeeming
        redeemFailure = nil
        do {
            switch try await gateway.redeem(code: code) {
            case let .credited(reward, referral):
                status = referral // taze durum (canRedeem artık false)
                redeemState = .credited(coins: reward.coins) // yalnız server onayında
                redeemCelebration += 1
                analytics.trackReferralRedeemed(coinReward: reward.coins, expiresAt: reward.expiresAt)
            case let .conflict(reason):
                if case let .alreadyRedeemed(fresh) = reason, let fresh {
                    status = fresh
                }
                redeemState = .conflict(reason) // kredi YOK; kullanıcıya-görünür
            }
        } catch {
            redeemState = .idle
            redeemFailure = Self.redeemFailure(for: error) // transport → retry
        }
    }

    // MARK: - İç: hata eşleme

    private static func loadFailure(for error: Error) -> LoadState {
        isConnectivity(error) ? .offline : .failed
    }

    private static func redeemFailure(for error: Error) -> RedeemFailure {
        isConnectivity(error) ? .offline : .generic
    }

    private static func isConnectivity(_ error: Error) -> Bool {
        guard case let AppError.network(networkError) = error else { return false }
        return networkError == .offline || networkError == .timeout
    }
}
