import DesignSystem
import SwiftUI

/// `DesignSystemCatalog` demo target'ının (SS-007) tek kaynağı: DSCatalogView'i
/// host eder. `ShortSeriesApp` target'ı bu dizini DERLEMEZ (project.yml excludes).
@main
struct CatalogApp: App {
    var body: some Scene {
        WindowGroup {
            DSCatalogView()
        }
    }
}
