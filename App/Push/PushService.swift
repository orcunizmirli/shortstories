import AppFoundation
import DiscoverKit
import Foundation

/// SS-140 + SS-143 — App push orkestratörü (03 §5 kompozisyon kökü altında). `AppDelegate` (UN/UIKit
/// seam) ham callback'leri buraya akıtır; bu tip UN/UIKit tipi GÖRMEZ (yalnız `Data` + `[AnyHashable:
/// Any]` + AppFoundation değer tipleri). Sorumluluklar:
///   1. APNs token → `DeviceTokenRegistering` (POST /devices; izin durumuyla).
///   2. Push'a dokunma → `PushPayload` çöz → `DeepLinkRoute` köprüsü + `push_open` atıf analitiği (08 §3.6).
///   3. Foreground/açılış → izin varsa token'ı tazele (rotasyon) + izin/ana-anahtar senkronu.
///
/// Rota dağıtımı `LaunchCoordinator.dispatch`e (enjekte closure) gider: soğuk açılışta `PendingRoute`,
/// sıcakta anında (03 §3.2 kural 6, 02 §5.6 adım 3). Saf parça (`openParameters`/`seriesID`) izole test edilir.
@MainActor
final class PushService {
    private let registrar: any DeviceTokenRegistering
    private let analytics: any AnalyticsTracking
    private let remoteRegistration: any RemoteNotificationRegistering
    private let authorization: any NotificationAuthorizationReading
    /// Kullanıcının uygulama-içi bildirim tercihi (ana anahtar) — `POST /devices notificationOptIn`.
    private let optInProvider: @MainActor () -> Bool
    /// Çözülmüş rotayı launch katmanına delege eder (soğuk açılış PendingRoute mantığı orada).
    private let dispatch: @MainActor (DeepLinkRoute, DeepLinkSource) -> Void

    init(
        registrar: any DeviceTokenRegistering,
        analytics: any AnalyticsTracking,
        remoteRegistration: any RemoteNotificationRegistering,
        authorization: any NotificationAuthorizationReading,
        optInProvider: @escaping @MainActor () -> Bool,
        dispatch: @escaping @MainActor (DeepLinkRoute, DeepLinkSource) -> Void
    ) {
        self.registrar = registrar
        self.analytics = analytics
        self.remoteRegistration = remoteRegistration
        self.authorization = authorization
        self.optInProvider = optInProvider
        self.dispatch = dispatch
    }

    // MARK: - Token kaydı (AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken)

    /// APNs `Data` token'ı alındığında (AppDelegate seam): kaydı fire-and-forget başlatır (delegate
    /// callback'i beklemez). Kayıt mantığı `registerToken(data:)`te — testler onu doğrudan await eder.
    func didRegisterToken(_ tokenData: Data) {
        Task { await registerToken(data: tokenData) }
    }

    /// Token'ı `DeviceToken`e çevirip mevcut izin durumuyla kaydeder (idempotent — registrar token/izin
    /// değişmedikçe POST etmez).
    func registerToken(data tokenData: Data) async {
        let token = DeviceToken(rawTokenData: tokenData)
        await registrar.registerToken(token, optIn: optInProvider())
    }

    // MARK: - Push'a dokunma (AppDelegate.userNotificationCenter didReceive / soğuk açılış)

    /// Ham `userInfo`'yu çözer; F1 dışı/bilinmeyen tip → SESSİZCE yok sayılır (02 §5.6, F1 kapsamı).
    /// (Test giriş noktası; canlı yolda `AppDelegate` payload'ı nonisolated çözer.)
    func handleOpenedPush(_ userInfo: [AnyHashable: Any]) {
        guard let payload = PushPayload(userInfo: userInfo) else { return }
        handleOpenedPush(payload)
    }

    /// `push_open` atar (08 §3.6) ve çözülmüş rotayı dağıtır (yeni bölüm → dizi/bölüm; devam-et →
    /// kaldığı yer). Rota çözülemezse yalnız atıf atılır (rota yutulur — 02 §8.4 bilinmeyen path).
    func handleOpenedPush(_ payload: PushPayload) {
        let route = DeepLinkRoute(url: payload.route)
        analytics.track("push_open", parameters: Self.openParameters(payload: payload, route: route))
        if let route {
            dispatch(route, .push)
        }
    }

    // MARK: - Açılış / foreground senkronu (SS-140 token rotasyonu + izin takibi)

    /// İzin varsa token'ı yeniden alır (05 §4.9 "her açılışta yeniden gönderilir" — registerToken
    /// idempotent optIn'i de senkronlar); ayrıca token beklemeden izin/ana-anahtar değişimini gönderir.
    func refreshRegistration() async {
        if await authorization.isAuthorized() {
            remoteRegistration.registerForRemoteNotifications()
        }
        // Token yoksa no-op (registrar kararı); varsa ana-anahtar değiştiyse POST optIn güncellenir.
        await registrar.updateOptIn(optInProvider())
    }

    // MARK: - Saf analitik eşlemesi (08 §3.6 `push_open`) — izole test edilir

    /// `push_open {push_type, campaign_id?, series_id?}` parametreleri (08 §3.6). `series_id` payload'da
    /// açıksa onu, yoksa çözülmüş rotadan (dizi/bölüm/play) türetir.
    static func openParameters(payload: PushPayload, route: DeepLinkRoute?) -> [String: AnalyticsValue] {
        var params: [String: AnalyticsValue] = ["push_type": .string(payload.type.rawValue)]
        if let campaignID = payload.campaignID {
            params["campaign_id"] = .string(campaignID)
        }
        if let seriesID = payload.seriesID ?? route.flatMap(seriesID(from:)) {
            params["series_id"] = .string(seriesID)
        }
        return params
    }

    /// Çözülmüş rotadan dizi kimliği (analitik `series_id`) — yalnız dizi/bölüm/play rotaları taşır.
    static func seriesID(from route: DeepLinkRoute) -> String? {
        switch route {
        case let .series(id): id.rawValue
        case let .episode(seriesId, _): seriesId.rawValue
        case let .play(seriesId, _): seriesId.rawValue
        default: nil
        }
    }
}
