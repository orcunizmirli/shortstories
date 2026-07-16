import Foundation

/// En son sunucuya gönderilen APNs kayıt anlık görüntüsü (SS-140 idempotent kayıt kararı). Token +
/// izin durumu; Keychain'de (`SecureStoreKey.pushRegistration`) JSON olarak kalıcıdır. `Equatable`
/// karşılaştırması "değişti mi?" kararının çekirdeğidir (aşağıdaki `DeviceRegistrationPlanner`).
struct DeviceRegistrationSnapshot: Equatable, Sendable, Codable {
    let apnsToken: String
    let notificationOptIn: Bool
}

/// Kayıt kararı — SAF, deterministik (deliverable 4: "token-kayıt kararı izole test"). Dış sistem yok.
enum DeviceRegistrationPlan: Equatable {
    /// POST /devices gerekli (yeni token veya izin değişti).
    case register(DeviceRegistrationSnapshot)
    /// Hiçbir şey değişmedi → ağ çağrısı YOK (idempotent).
    case skip
}

/// APNs kayıt kararının saf çekirdeği (SS-140). Idempotentlik + "token/izin değişiminde yeniden kayıt"
/// kuralı burada; `LiveDeviceTokenRegistrar` yalnız I/O (Keychain okuma + POST) sarar.
enum DeviceRegistrationPlanner {
    /// Token geldiğinde (`didRegisterForRemoteNotificationsWithDeviceToken`): yeni (token, optIn)
    /// son gönderilenden FARKLIYSA POST; AYNIYSA skip (idempotent — aynı token tekrar tekrar gelse de
    /// tek POST).
    static func planForToken(
        token: String,
        optIn: Bool,
        lastSent: DeviceRegistrationSnapshot?
    ) -> DeviceRegistrationPlan {
        let candidate = DeviceRegistrationSnapshot(apnsToken: token, notificationOptIn: optIn)
        return candidate == lastSent ? .skip : .register(candidate)
    }

    /// İzin durumu (token değişmeden) değiştiğinde: HİÇ token gönderilmemişse skip (izin yoksa/token
    /// yoksa kayıt yok — kayıt token geldiğinde kurulur). Varsa aynı token'la optIn güncellenir; değer
    /// gerçekten değiştiyse POST (05 §4.9: "tercih kapatıldığında notificationOptIn: false ile güncelle").
    static func planForOptInChange(
        optIn: Bool,
        lastSent: DeviceRegistrationSnapshot?
    ) -> DeviceRegistrationPlan {
        guard let lastSent else { return .skip }
        let candidate = DeviceRegistrationSnapshot(apnsToken: lastSent.apnsToken, notificationOptIn: optIn)
        return candidate == lastSent ? .skip : .register(candidate)
    }
}

/// `POST /devices` — APNs token kaydı; upsert semantiği (aynı `deviceId` günceller, 05 §4.9 tablo satır
/// 29). Auth gerektirir; retry YOK (POST idempotency-key taşımaz — başarısızlıkta bir sonraki
/// açılış/izin değişimi yeniden dener). Yanıt `204 No Content` → `EmptyResponse`.
struct DeviceRegistrationEndpoint: Endpoint {
    struct Body: Encodable, Equatable {
        let deviceId: String
        let apnsToken: String
        let environment: String
        let locale: String
        let timezone: String
        let notificationOptIn: Bool
    }

    typealias Response = EmptyResponse

    let requestBody: Body

    var path: String {
        "/devices"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        requestBody
    }

    var requiresAuth: Bool {
        true
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}
