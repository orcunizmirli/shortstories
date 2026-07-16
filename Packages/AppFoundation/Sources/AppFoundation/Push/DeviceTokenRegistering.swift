import Foundation

/// APNs cihaz token'ı KAYIT portu (SS-140). App delegate seam'i ham APNs `Data`'sını `DeviceToken`'a
/// çevirip bu portu çağırır; canlı impl backend'e `POST /devices` gönderir (token, ortam, dil, saat
/// dilimi, izin durumu — 05 §4.9). Idempotent: token/izin değişmedikçe tekrar POST etmez. UN/UIKit
/// tipleri bu port'a GEÇMEZ (03 §10.1 katman sınırı) → gerçek APNs olmadan mock APIClient ile test edilir.
public protocol DeviceTokenRegistering: Sendable {
    /// APNs token alındığında (`didRegisterForRemoteNotificationsWithDeviceToken`) çağrılır. `optIn`
    /// = kullanıcının uygulama-içi bildirim tercihi (ana anahtar). Token/izin bir öncekiyle aynıysa no-op.
    func registerToken(_ token: DeviceToken, optIn: Bool) async

    /// İzin durumu token değişmeden değiştiğinde (Ayarlar ana anahtarı / OS düzeyi) çağrılır — son
    /// gönderilen token'la `notificationOptIn` güncellenir. Hiç token yoksa no-op (05 §4.9: kayıt silinmez).
    func updateOptIn(_ optIn: Bool) async
}

/// Canlı APNs kayıt uygulaması (SS-140). `actor`: eşzamanlı token/izin çağrılarını serileştirir; kayıt
/// kararı saf `DeviceRegistrationPlanner`'dan gelir, bu tip yalnız Keychain okuma + POST I/O'sunu sarar.
/// `deviceId` `SessionManager` ile AYNI Keychain anahtarını (`.deviceID`) paylaşır → misafir bootstrap
/// ile birebir cihaz kimliği (reinstall'da devam kanonu, 05 §4.2).
public actor LiveDeviceTokenRegistrar: DeviceTokenRegistering {
    private let apiClient: any APIClientProtocol
    private let secureStore: any SecureStoring
    private let environment: APNsEnvironment
    private let logger: any Logging
    private let localeProvider: @Sendable () -> String
    private let timezoneProvider: @Sendable () -> String

    public init(
        apiClient: any APIClientProtocol,
        secureStore: any SecureStoring,
        environment: APNsEnvironment,
        logger: any Logging,
        localeProvider: @escaping @Sendable () -> String = { Locale.current.identifier(.bcp47) },
        timezoneProvider: @escaping @Sendable () -> String = { TimeZone.current.identifier }
    ) {
        self.apiClient = apiClient
        self.secureStore = secureStore
        self.environment = environment
        self.logger = logger
        self.localeProvider = localeProvider
        self.timezoneProvider = timezoneProvider
    }

    public func registerToken(_ token: DeviceToken, optIn: Bool) async {
        let plan = DeviceRegistrationPlanner.planForToken(
            token: token.hexString,
            optIn: optIn,
            lastSent: loadSnapshot()
        )
        await apply(plan)
    }

    public func updateOptIn(_ optIn: Bool) async {
        let plan = DeviceRegistrationPlanner.planForOptInChange(optIn: optIn, lastSent: loadSnapshot())
        await apply(plan)
    }

    private func apply(_ plan: DeviceRegistrationPlan) async {
        guard case let .register(snapshot) = plan else { return }
        let endpoint = DeviceRegistrationEndpoint(requestBody: DeviceRegistrationEndpoint.Body(
            deviceId: deviceID(),
            apnsToken: snapshot.apnsToken,
            environment: environment.rawValue,
            locale: localeProvider(),
            timezone: timezoneProvider(),
            notificationOptIn: snapshot.notificationOptIn
        ))
        do {
            _ = try await apiClient.send(endpoint)
            // Yalnız BAŞARIDA snapshot yazılır: hata sonrası snapshot değişmez → bir sonraki
            // açılış/izin değişimi aynı POST'u yeniden dener (AppDelegate: "retry stratejisi yok").
            saveSnapshot(snapshot)
            logger.info("push: cihaz kaydı güncellendi (optIn=\(snapshot.notificationOptIn))")
        } catch {
            // PII kuralı (03 §10.3): token/hata gövdesi loglanmaz.
            logger.error("push: cihaz kaydı başarısız (bir sonraki açılışta yeniden denenecek)")
        }
    }

    /// SessionManager ile AYNI kalıcı cihaz kimliği (`.deviceID`); yoksa üretilip yazılır.
    private func deviceID() -> String {
        if let existing = try? secureStore.string(forKey: .deviceID), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        try? secureStore.setString(newID, forKey: .deviceID)
        return newID
    }

    private func loadSnapshot() -> DeviceRegistrationSnapshot? {
        // `try?` bir sonucu (Keychain hatası ya da anahtar yoksa) `nil`e düzler → tek unwrap yeter.
        guard let data = try? secureStore.data(forKey: .pushRegistration) else { return nil }
        return try? JSONDecoder().decode(DeviceRegistrationSnapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: DeviceRegistrationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? secureStore.setData(data, forKey: .pushRegistration)
    }
}
