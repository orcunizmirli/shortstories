// R1 İSTİSNASI: AppFoundation UI içermez (03 §4 R1) — SwiftUI import'u paket genelinde
// YALNIZ bu dosyadadır. 03 §5.2 EnvironmentKey köprüsünü açıkça AppFoundation'a koyar;
// bağımlılık lint'i bu dosyayı bilerek muaf tutar.
import SwiftUI

public extension EnvironmentValues {
    // Cross-cutting servis erişimi (analytics, feature flag, theme — 03 §5.2).
    // ViewModel bağımlılıkları HER ZAMAN init-injection'dır; Environment yalnız derin
    // view ağaçlarındaki cross-cutting ihtiyaçlar içindir.
    // `defaultValue` `PreviewDependencies` olduğundan her `#Preview` sıfır
    // konfigürasyonla çalışır.
    @Entry var dependencies: any Dependencies = PreviewDependencies()
}
