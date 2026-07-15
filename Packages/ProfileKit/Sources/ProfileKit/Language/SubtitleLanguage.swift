/// Altyazı dili tercihi (SS-161) — uygulama dilinden BAĞIMSIZ değer tipi. PlayerKit (SS-046) bu
/// tercihi `SubtitleLanguageProviding` üzerinden okur ve `AVMediaSelectionGroup`'ta eşleşen
/// track'i seçer. Uygulama dilinden farklı olarak altyazı kodu izin listesine tabi DEĞİLDİR: sunucu
/// bir dizide UI listesinden daha fazla altyazı dili sunabilir; kullanıcı seçimi korunur.
/// `code == nil` = altyazı kapalı.
public struct SubtitleLanguage: Sendable, Equatable, Hashable, Identifiable {
    /// `nil` = altyazı kapalı; aksi halde BCP-47 birincil alt-etiket.
    public let code: String?

    public var id: String {
        code ?? Self.offSentinel
    }

    public init(code: String?) {
        self.code = code
    }

    public static let off = SubtitleLanguage(code: nil)
    public static let english = SubtitleLanguage(code: "en")
    public static let turkish = SubtitleLanguage(code: "tr")
    public static let spanish = SubtitleLanguage(code: "es")
    public static let portuguese = SubtitleLanguage(code: "pt")

    public var isOff: Bool {
        code == nil
    }

    /// Dilin kendi adı (endonym); kapalıysa `nil` (View "Kapalı" gösterir).
    public var displayName: String? {
        code.map { LanguageCatalog.endonym(forCode: $0) }
    }

    // MARK: - Kalıcı (UserDefaults) temsili

    /// "Kapalı" (code == nil) durumunun kalıcı/kimlik sentinel'i. BCP-47 birincil alt-etiketi ASLA
    /// boş olamaz → boş dize sentinel'i, kodu literal "off" (veya başka herhangi bir kod) olan GERÇEK
    /// sunucu track'iyle ÇAKIŞMAZ; sentinel değer uzayının dışındadır (review #9). Böylece
    /// "sunucu track'i birebir korunur" sözü tutulur: `SubtitleLanguage(code: "off")` altyazı-kapalıya
    /// round-trip OLMAZ, kullanıcı seçimi sessizce kaybolmaz.
    static let offSentinel = ""

    /// Saklı koddan çözer: sentinel (boş) → kapalı; aksi halde o kod (gerçek track korunur).
    public init(persistedCode: String) {
        self = persistedCode == Self.offSentinel ? .off : SubtitleLanguage(code: persistedCode)
    }

    /// UserDefaults'a yazılan değer: kapalı → sentinel (boş); aksi halde kodun kendisi.
    public var persistedValue: String {
        code ?? Self.offSentinel
    }
}
