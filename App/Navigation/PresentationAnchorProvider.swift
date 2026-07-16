import AuthenticationServices
import UIKit

/// Apple ile Giriş sunum çıpası sağlayıcı (SS-132). `AppleSignInService` çıpayı App'ten ister
/// (`ASAuthorizationController` aktif pencereyi bilmelidir); kompozisyon kökü aktif key window'u
/// döndürür. Pencere yoksa (test/erken açılış) yeni boş pencere döner — kilitlenme yerine no-op.
enum PresentationAnchorProvider {
    @MainActor
    static func anchor() -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        if let keyWindow = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first {
            return keyWindow
        }
        return ASPresentationAnchor()
    }
}
