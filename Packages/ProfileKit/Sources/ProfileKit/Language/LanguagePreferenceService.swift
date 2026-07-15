import AppFoundation
import Foundation

/// SS-161 uygulama + altyazı dili tercihlerinin çalışma-zamanı TEK KAYNAĞI. `PreferencesStoring`'e
/// kalıcı yazar (kalıcılığın tek kaynağı odur) ve değişimi `AsyncMulticast` ile ANINDA yayınlar.
/// `SubtitleLanguageProviding`/`AppLanguageProviding` uyumu ile PlayerKit (SS-046) ve App bu
/// tercihi ProfileKit'i tek yönlü tüketerek okur (R2/R8). `AyarlarModel` yazar; player/App okur.
///
/// Concurrency: dil durumu `NSLock` ile korunur (cross-actor okunabilsin) — bu yüzden @Observable
/// DEĞİL; SwiftUI tarafı `AyarlarModel`'in @Observable aynasından beslenir.
public final class LanguagePreferenceService: SubtitleLanguageProviding, AppLanguageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let preferences: any PreferencesStoring
    private var app: AppLanguage
    private var subtitle: SubtitleLanguage
    private let appMulticast = AsyncMulticast<AppLanguage>()
    private let subtitleMulticast = AsyncMulticast<SubtitleLanguage>()

    public init(preferences: any PreferencesStoring) {
        self.preferences = preferences
        let storedAppCode = preferences.value(for: ProfilePreferenceKeys.appLanguageCode)
        let subtitleCode = preferences.value(for: PreferenceKeys.subtitleLanguageCode)
        let resolvedApp = LanguageCatalog.appLanguage(forStoredCode: storedAppCode)
        app = resolvedApp
        subtitle = LanguageCatalog.subtitleLanguage(forStoredCode: subtitleCode)
        // Geçersiz/desteklenmeyen app-language kodu kalıcı ise çözülen değeri UserDefaults'a GERİ YAZ:
        // yalnız bellekte .default'a düşmek yetmez — changed-guard yüzünden geçersiz kod aksi halde
        // kalıcı kalır (review #8). Altyazı izin listesine tabi DEĞİL → geri-yazma yok.
        if resolvedApp.code != storedAppCode {
            preferences.set(resolvedApp.code, for: ProfilePreferenceKeys.appLanguageCode)
        }
        // Geç abonelerin replay'i için mevcut değeri tohumla.
        appMulticast.send(app)
        subtitleMulticast.send(subtitle)
    }

    // MARK: - Okuma (AppLanguageProviding / SubtitleLanguageProviding)

    public var appLanguage: AppLanguage {
        lock.withLock { app }
    }

    public var currentSubtitleLanguage: SubtitleLanguage {
        lock.withLock { subtitle }
    }

    public func appLanguageUpdates() -> AsyncStream<AppLanguage> {
        appMulticast.subscribe()
    }

    public func subtitleLanguageUpdates() -> AsyncStream<SubtitleLanguage> {
        subtitleMulticast.subscribe()
    }

    // MARK: - Yazma (yalnız AyarlarModel / Onboarding çağırır)

    /// Değer gerçekten değiştiyse `true` döner (çağıran analitik yalnız değişimde atsın).
    @discardableResult
    public func setAppLanguage(_ value: AppLanguage) -> Bool {
        // Mutasyon + persist + broadcast AYNI kritik bölümde: eşzamanlı yazarlar bu üçlüyü
        // bellek-içi değere göre sırasız commit edemez (review #7). `preferences.set` ve
        // `multicast.send` bu paketin dışına geri çağrı yapmaz → kilit içinde güvenli.
        lock.withLock {
            guard app != value else { return false }
            app = value
            preferences.set(value.code, for: ProfilePreferenceKeys.appLanguageCode)
            appMulticast.send(value)
            return true
        }
    }

    @discardableResult
    public func setSubtitleLanguage(_ value: SubtitleLanguage) -> Bool {
        lock.withLock {
            guard subtitle != value else { return false }
            subtitle = value
            preferences.set(value.persistedValue, for: PreferenceKeys.subtitleLanguageCode)
            subtitleMulticast.send(value)
            return true
        }
    }
}
