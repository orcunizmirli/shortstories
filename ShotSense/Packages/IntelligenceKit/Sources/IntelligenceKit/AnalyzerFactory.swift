import AppFoundation
import ShotCore

/// Cihazın yeteneğine ve kullanıcı tercihine göre analiz yolunu seçer.
///
/// Kompozisyon kökü (App target) bunu çağırır; hiçbir özellik paketi hangi analizörün
/// kullanıldığını bilmez — yalnız `ShotAnalyzing` portunu görür (R3).
public enum AnalyzerFactory {
    public static func make(flags: FeatureFlags = .default) async -> any ShotAnalyzing {
        guard flags.intelligenceEnabled else {
            Log.info(.intelligence, "Zekâ modu kullanıcı tarafından kapatılmış; heuristik yol")
            return HeuristicAnalyzer()
        }

        let analyzer = FoundationModelAnalyzer()
        guard await analyzer.isAvailable else {
            Log.info(
                .intelligence,
                "Apple Intelligence kullanılamıyor; heuristik yol",
                detail: FoundationModelAnalyzer.availabilityDescription()
            )
            return HeuristicAnalyzer()
        }
        return analyzer
    }
}
