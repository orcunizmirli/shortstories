import AnalyticsKit
import AppFoundation

/// SS-024 + SS-154 — remote config (Splash fetch + force-update verisi) + A/B deney grafiği kurulumu.
/// Kompozisyon kökü ana dosyadan ayrılan bu extension'da yaşar (`AppComposition+FeatureModels` kalıbı):
/// `init` tek fabrikayı çağırır, kurulum ayrıntısı ve tüketici yüzeyi (fetch/force-update) burada.
///
/// UZLAŞMA (docs/08 §7 + 05 §4.10 OKUNDU): `GET /config.experiments` server-OTORİTER atama taşır
/// (`{ key, variant }`); client-side deterministik bucketing (08 §7.2) offline/fallback'tir. Server atama
/// KAZANIR → `RemoteExperimentBridge` bunu `DeterministicExperimentAssigner.serverAssignments` override'ına
/// köprüler (SS-154 API kırılmaz) ve exposure için minimal katalog sentezler.
@MainActor
extension AppComposition {
    // MARK: - Kurulum (init'ten tek çağrı)

    /// Remote config istemcisi + A/B deney grafiğinin kompozisyon-kökü sonucu (init stored `let`'lerini
    /// besler). Tek fabrikadan döner → `init` gövdesi kısa kalır.
    struct ConfigGraph {
        let remoteConfig: any RemoteConfigProviding
        let client: ExperimentClient
        let decorated: ExperimentDimensionTracker
        /// Exposure geçmişi deposu — App bunu tutar, scenePhase-bg'de `client.exposedExperimentKeys`'i persist eder.
        let exposedExperimentsStore: UserDefaultsExposedExperimentsStore
    }

    /// Remote config istemcisi + deney grafiğini BİRLİKTE kurar. Cache'li config (freeze-per-launch,
    /// 03 §11) deney atamalarını + `minSupportedVersion`'ı besler; taze fetch Splash'ta bir sonraki
    /// launch'a yazılır. `decoratedAnalytics` BASE'i sarar (§7.3 exposure BASE'e gider). userID = deviceID
    /// (Keychain kalıcı → sticky atama). `previouslyExposed` `UserDefaultsExposedExperimentsStore`'dan
    /// tohumlanır; scenePhase-bg persist `AppComposition.persistExposedExperiments()`.
    static func makeConfigGraph(dependencies: any Dependencies) -> ConfigGraph {
        let remoteConfig = RemoteConfigClient(apiClient: dependencies.apiClient, logger: dependencies.logger)
        let deviceID = (try? dependencies.secureStore.string(forKey: .deviceID)) ?? ""
        // Cache'li server atamaları (yoksa boş → pasif/kontrol, exposure yok) → köprü → deney istemcisi.
        let bridge = RemoteExperimentBridge(assignments: remoteConfig.cachedConfig()?.experiments ?? [])
        // Exposure geçmişi (kalıcı) → `previouslyExposed` tohumu: DÖNEN kullanıcı `first_exposure=true` DÜŞMEZ.
        let exposedStore = UserDefaultsExposedExperimentsStore()
        let client = bridge.makeExperimentClient(
            analytics: dependencies.analytics, userID: deviceID, previouslyExposed: exposedStore.load()
        )
        // `abVariants` closure `@Sendable` (`ExperimentClient` `@unchecked Sendable`, kilitli okuma).
        let decorated = ExperimentDimensionTracker(base: dependencies.analytics, abVariants: { client.abVariantsParameter() })
        return ConfigGraph(
            remoteConfig: remoteConfig, client: client, decorated: decorated, exposedExperimentsStore: exposedStore
        )
    }

    /// scenePhase `.background` → bu oturumda maruz kalınan deney anahtarlarını kalıcı depoya birleştirir
    /// (08 §7.3). Bir sonraki launch `previouslyExposed` olarak okur → DÖNEN kullanıcı `first_exposure`
    /// yanlışça `true` DÜŞMEZ. Boş oturumda (exposure yok) yazma yapılmaz.
    func persistExposedExperiments() {
        exposedExperimentsStore.merge(experimentClient.exposedExperimentKeys)
    }

    // MARK: - Tüketici yüzeyi (Splash fetch + force-update verisi)

    /// SS-024 Splash soğuk açılış config fetch'i (05 §13.1: `/auth/guest` + `/feed` ile PARALEL çağrılır).
    /// Taze cache varsa ağ YOK (24h TTL); yoksa refresh → cache + flag snapshot bir SONRAKİ launch'a
    /// yazılır (freeze-per-launch, 03 §11). GRACEFUL: offline/bozuk → cache/nil döner, throw ETMEZ,
    /// Splash bloklanmaz. Bu oturumun atama/flag'lerini DEĞİŞTİRMEZ (oturum ortası sabit, 08 §7.1).
    @discardableResult
    func refreshRemoteConfig() async -> RemoteConfig? {
        await remoteConfig.loadForColdStart()
    }

    /// SS-024 force-update verisi (02 §4.16 overlay UI AYRI/TODO — bu görevde YALNIZ veri): son bilinen
    /// zorunlu minimum istemci sürümü. Cache yoksa "0.0.0" (hiçbir sürümü bloklamayan güvenli varsayılan).
    var minSupportedVersion: String {
        remoteConfig.cachedConfig()?.minSupportedVersion ?? "0.0.0"
    }
}
