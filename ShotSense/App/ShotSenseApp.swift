import AppFoundation
import ShotCore
import SwiftUI

/// Uygulamanın giriş noktası ve **kompozisyon köküdür** (03 §1).
///
/// Adaptörlerin (`OCRKit`, `IntelligenceKit`, `IngestKit`, `IndexKit`, `ActionKit`, `PaywallKit`)
/// portlara bağlandığı tek yer burasıdır; hiçbir özellik paketi başka bir adaptörü göremez.
@main
struct ShotSenseApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}

/// Portların somut adaptörlere bağlandığı kapsayıcı.
///
/// Şu an yalnız iskelet: adaptörler M1–M5 boyunca sırayla takılacak (08-yol-haritasi.md).
@MainActor
@Observable
final class AppContainer {
    let flags: FeatureFlags
    let analytics: AnalyticsRecorder

    init(flags: FeatureFlags = .default) {
        self.flags = flags
        analytics = AnalyticsRecorder()
        Log.info(.lifecycle, "AppContainer kuruldu")
    }
}

struct RootView: View {
    var body: some View {
        // TODO(SS-041): LibraryKit'in TabView kökü buraya bağlanacak (02 §1).
        ContentUnavailableView(
            "ShotSense",
            systemImage: "sparkle.magnifyingglass",
            description: Text("Kitaplık arayüzü M4'te bağlanacak.")
        )
    }
}
