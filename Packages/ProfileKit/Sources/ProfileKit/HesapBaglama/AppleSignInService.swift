import AuthenticationServices
import Foundation

/// Canlı Sign in with Apple servisi (SS-132). `ASAuthorizationController` + delegate/continuation
/// burada HAPSOLUR (R6, StoreKit sarmalı kalıbı `StoreKitPurchaseService` ile birebir): ham
/// `ASAuthorization`/`ASAuthorizationAppleIDCredential` dışarı SIZMAZ, yalnız SAF `AppleCredential`
/// döner. Testlerde fake port kullanılır — bu tip birim testine girmez (UI/entegrasyon sınırı).
///
/// `@MainActor`: `ASAuthorizationController.performRequests()` ve sunum ana thread ister; sınıf bu
/// yüzden main-actor izole ve dolayısıyla `Sendable` (port `Sendable` sözleşmesini karşılar).
@MainActor
public final class AppleSignInService: NSObject, AppleSignInProviding {
    /// Sunum çıpası (genelde aktif pencere) — App enjekte eder; ham UIKit ProfileKit modeline sızmaz.
    private let anchorProvider: @MainActor () -> ASPresentationAnchor
    /// Kaynak-güvenli tek-uçuş continuation çekirdeği (reentrancy + stale-callback koruması burada).
    private let coordinator = AppleSignInCoordinator()
    /// Uçuştaki controller GÜÇLÜ tutulur: aksi halde yerel değişken çözülür, Apple callback GELMEZ ve
    /// Model `.linking`'de KALICI kilitlenir (yaşam süresi garantisi).
    private var activeController: ASAuthorizationController?

    public init(anchor: @escaping @MainActor () -> ASPresentationAnchor) {
        anchorProvider = anchor
        super.init()
    }

    public func requestCredential() async throws -> AppleCredential {
        // Reentrancy: önceki controller'ın delegate'ini GEÇERSİZ kıl → gecikmeli callback'i yeni
        // continuation'ı bozamaz (coordinator ayrıca controller-kimliği ile stale'i eler; savunma derinliği).
        activeController?.delegate = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { cont in
            activeController = controller // güçlü referans: yaşam süresi garanti
            coordinator.begin(cont, controller: controller) // önceki askı `cancelled` ile biter
            controller.performRequests()
        }
    }

    /// Delegate callback'i çözüldükten sonra uçuştaki controller referansını bırak (yalnız güncelse).
    private func clearActiveController(_ controller: ASAuthorizationController) {
        if controller === activeController {
            activeController = nil
        }
    }

    /// SAF kimlik-bilgisi doğrulama/haritalama — `ASAuthorization`'dan AYRIK (deterministik test
    /// edilir; gerçek Apple UI gerekmez). Boş/whitespace `identityToken` backend'e GİTMEZ.
    nonisolated static func makeCredential(
        identityToken: String?,
        authorizationCode: String?,
        userIdentifier: String,
        email: String?,
        fullName: String?
    ) -> Result<AppleCredential, Error> {
        // Boş/whitespace-yalnızca identityToken beklenmedik yanıttır: boş JWT backend'e GİTMEZ
        // (boş `Data` → "" tuzağı). Yalnız içerikli token geçer.
        guard
            let identityToken,
            !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failure(AppleSignInError.invalidResponse)
        }
        let cleanedName = fullName?.trimmingCharacters(in: .whitespaces)
        return .success(AppleCredential(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            userIdentifier: userIdentifier,
            email: email,
            fullName: (cleanedName?.isEmpty == false) ? cleanedName : nil
        ))
    }

    private func mapCredential(_ authorization: ASAuthorization) -> Result<AppleCredential, Error> {
        // Ham `ASAuthorization` yalnız BURADA çözülür (Data→String); doğrulama+haritalama SAF
        // `makeCredential`'da (test edilebilir tek kapı).
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return .failure(AppleSignInError.invalidResponse)
        }
        let identityToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let fullName = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
        return Self.makeCredential(
            identityToken: identityToken,
            authorizationCode: authCode,
            userIdentifier: credential.user,
            email: credential.email,
            fullName: fullName
        )
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        coordinator.finish(from: controller, with: mapCredential(authorization))
        clearActiveController(controller)
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let mapped: AppleSignInError = (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .failed
        coordinator.finish(from: controller, with: .failure(mapped))
        clearActiveController(controller)
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        anchorProvider()
    }
}

/// Tek-uçuş continuation koordinatörü — `AppleSignInService`'in kaynak-güvenli çekirdeği,
/// `AuthenticationServices`'ten BAĞIMSIZ (deterministik test edilir). Reentrancy'de önceki askı
/// `cancelled` ile biter; yalnız GÜNCEL controller'ın callback'i continuation'ı çözer (gecikmeli/stale
/// callback yeni continuation'ı ESKİ sonuçla resume EDEMEZ → çapraz-kablo koruması, savunma derinliği).
@MainActor
final class AppleSignInCoordinator {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var activeController: AnyObject?

    /// Askı var mı (test gözlem kancası).
    var isSuspended: Bool {
        continuation != nil
    }

    /// Yeni uçuş kaydı — önceki askıdaki varsa `cancelled` ile bitir (aynı anda tek akış).
    func begin(_ cont: CheckedContinuation<AppleCredential, Error>, controller: AnyObject) {
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: AppleSignInError.cancelled)
        }
        continuation = cont
        activeController = controller
    }

    /// Sonucu continuation'a taşı — YALNIZ güncel controller'ın callback'i. Gecikmeli/stale controller
    /// (reentrancy'de geçersiz kılınan önceki uçuş) yeni continuation'ı ESKİ sonuçla resume edemez.
    func finish(from controller: AnyObject, with result: Result<AppleCredential, Error>) {
        guard controller === activeController, let cont = continuation else { return }
        continuation = nil
        activeController = nil
        cont.resume(with: result)
    }
}
