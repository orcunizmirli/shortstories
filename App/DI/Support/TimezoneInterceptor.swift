import AppFoundation
import Foundation

/// `X-Timezone: <IANA id>` header'ını HER isteğe ekler (05 §2.9; `requiresAuth`/method farketmez —
/// GET okumalar dahil). Sunucu `daily` görev/`checkin` "bugün" penceresini bu header'dan çözer
/// (05 §2.9, §4.7); istemci ASLA cihaz saatinden türetmez — saat oynamasına dayanıklılık.
///
/// Neden interceptor: `Endpoint` özel header taşıyamaz, bu yüzden çapraz-kesen timezone tek bir
/// kompozisyon-kökü halkasında toplanır (kalıp: `AuthInterceptor`). Böylece claim gövdesine timezone
/// koyma (eski, kırılgan) yolu tamamen kalkar ve okuma uçları da timezone taşır.
public struct TimezoneInterceptor: RequestInterceptor {
    private let timeZoneID: @Sendable () -> String

    public init(timeZoneID: @escaping @Sendable () -> String = { TimeZone.current.identifier }) {
        self.timeZoneID = timeZoneID
    }

    public func adapt(_ request: URLRequest, context _: RequestContext) async throws -> URLRequest {
        var adapted = request
        adapted.setValue(timeZoneID(), forHTTPHeaderField: "X-Timezone")
        return adapted
    }
}
