import Foundation

/// Saf altyazı-track eşleştirici (SS-046). `AVMediaSelectionOption`'lar bu değer tipine indirgenip
/// verilir; KARAR burada üretilir, `AVPlayerBackend` yalnız uygular (`item.select`). Böylece tüm mantık
/// CI birim testinde koşar (gerçek AVPlayer backend'i sim/cihaz-perf koşusunda; `StallTracker` deseni).
/// Hedef dil `String?` (BCP-47 birincil alt-etiket, PlayerKit ProfileKit'i görmez; nil = kapalı).
public enum SubtitleTrackSelector {
    /// Bir legible `AVMediaSelectionOption`'ın saf temsili.
    struct Option: Equatable, Sendable {
        /// `group.options` içindeki konum — `item.select(group.options[index], in: group)` bununla yapılır.
        let index: Int
        /// `opt.extendedLanguageTag ?? opt.locale?.identifier` (BCP-47; ör. "en", "pt-BR").
        let languageTag: String?

        init(index: Int, languageTag: String?) {
            self.index = index
            self.languageTag = languageTag
        }
    }

    enum Decision: Equatable, Sendable {
        /// `item.select(group.options[index], in: group)`.
        case select(index: Int)
        /// Altyazı kapalı — `item.select(nil, in: group)` (grup empty selection'a izin veriyorsa).
        case off
    }

    /// nil/boş kod → `.off`. Aksi halde BCP-47 birincil alt-etiketi eşleşen İLK option. Hiç eşleşme
    /// yoksa `.off` (asset bu dili sunmuyor; kullanıcı tercihi persist'te korunur). "pt" ↔ "pt-BR" eşleşir.
    static func decide(preferredCode: String?, available options: [Option]) -> Decision {
        guard let wanted = primarySubtag(preferredCode) else {
            return .off
        }
        for option in options where primarySubtag(option.languageTag) == wanted {
            return .select(index: option.index)
        }
        return .off
    }

    /// BCP-47 birincil alt-etiket: küçük harf, "-"/"_" öncesi ilk bileşen. Boş/nil → nil. `public`:
    /// altyazı MENÜSÜ (App) de bunu kullanmalı — seçici track'i primary-subtag'le eşleştirdiğinden,
    /// menü exact `contains` kullanırsa "pt-BR" gibi sunucu kodları menüden gizlenip seçilebilir track
    /// kaybolur (adversarial review bulgusu). Menü ile seçim AYNI normalleştirmeden geçmeli.
    public static func primarySubtag(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty else {
            return nil
        }
        let primary = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return primary.map(String.init)
    }
}
