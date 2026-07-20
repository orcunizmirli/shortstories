import Foundation

/// İstemci fraud danışma sinyallerini isteklere HEADER olarak ekleyen interceptor (SS-100, F2;
/// kalıp: `AuthInterceptor`/`TimezoneInterceptor`). DEFANSİF: istemci karar VERMEZ, yalnız advisory
/// bayrak taşır — anormal-kazanç/tamper KARARINI backend verir (05 §1 kural 2; 09 R6).
///
/// Kapsam: yalnız `requiresAuth` (cüzdan/kazanç dahil authed) isteklere eklenir — misafir bootstrap/
/// refresh (`requiresAuth=false`) uçlarına fraud header GİTMEZ (`AuthInterceptor` `Bearer` gate'iyle
/// aynı kural; `RequestContext` genişletmeye gerek yok — en minimal yol).
///
/// Cihaz bütünlüğü prob'u kompozisyonda TEK KEZ değerlenir (jailbreak durumu process ömrü boyunca
/// değişmez; per-istek dosya-sistemi/yazma denemesi maliyeti önlenir) ve sonuç Sendable değer olarak
/// taşınır. Kazanç-hızı port'u (WalletKit faz 2'de sağlar) HER istekte taze sorgulanır (zamanla değişir);
/// `nil` dönerse velocity header eklenmez.
public struct FraudSignalInterceptor: RequestInterceptor {
    private let integrity: DeviceIntegritySignal
    private let velocityReporter: (any EarnVelocityReporting)?

    /// - Parameters:
    ///   - probe: cihaz bütünlüğü prob'u; `init`'te TEK KEZ değerlenir (sahtelenebilir → test gerçek
    ///     OS-probe çağırmaz).
    ///   - velocityReporter: kazanç-hızı danışma kaynağı (WalletKit faz 2'de bağlar); `nil` ise velocity
    ///     header hiç eklenmez.
    public init(probe: any DeviceIntegrityProbing, velocityReporter: (any EarnVelocityReporting)? = nil) {
        integrity = probe.evaluate()
        self.velocityReporter = velocityReporter
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        guard context.requiresAuth else {
            return request
        }
        let velocity = await velocityReporter?.currentEarnVelocity()
        let signal = FraudSignal(integrity: integrity, earnVelocity: velocity)
        var adapted = request
        for (name, value) in FraudSignalHeaders.fields(for: signal) {
            adapted.setValue(value, forHTTPHeaderField: name)
        }
        return adapted
    }
}
