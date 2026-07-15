/// Altyazı dili OKUMA portu (SS-161 → SS-046). PlayerKit bu portu tüketir; canlı uygulama
/// ProfileKit `LanguagePreferenceService`'e bağlanır — App DI kompozisyonunda (R2: PlayerKit
/// ProfileKit'i import etmeden altyazı tercihine bağlanır; R8: port tüketici-tarafında değil
/// ÜRETİCİ ProfileKit'te tanımlıdır — LibraryKit `LibraryCatalogReading` kalıbıyla aynı).
///
/// Değişiklik ANINDA yayınlanır: `subtitleLanguageUpdates()` current-value replay'li bir akıştır;
/// aktif player yeni tercihi sonraki segment sınırında uygular (02 §4.14).
public protocol SubtitleLanguageProviding: Sendable {
    /// Anlık altyazı dili tercihi (senkron okuma).
    var currentSubtitleLanguage: SubtitleLanguage { get }

    /// Tercih değişim akışı; abone olunca mevcut değeri replay ederek başlar.
    func subtitleLanguageUpdates() -> AsyncStream<SubtitleLanguage>
}

/// Uygulama dili OKUMA portu (SS-161). App bunu SwiftUI locale environment'ını yeniden inject
/// etmek için okur (02 §4.14: uygulama dili değişimi yeniden başlatma gerektirmez).
public protocol AppLanguageProviding: Sendable {
    var appLanguage: AppLanguage { get }
    func appLanguageUpdates() -> AsyncStream<AppLanguage>
}
