import ContentKit

/// SS-064 / ONB-04 — Onboarding tür tercihi adımının GÖMÜLÜ (offline) tür listesi. 02 §4.2:
/// "tür listesi bundle'da gömülü; remote config ile güncellenebilir ama fallback gömülüdür." 8-12
/// kart aralığı (ONB-04). ContentKit `Genre` değer tipi kullanılır (kanon: "ContentKit tür listesi");
/// `id` ilk For You sinyaline gider (05 API sözleşmesi), `name` kart etiketidir.
enum OnboardingGenreCatalog {
    /// Gömülü fallback (kısa-drama kanonik türleri). Sıra = kart ızgarası sırası (deterministik).
    static let embedded: [Genre] = [
        Genre(id: "romance", name: "Romantik", iconURL: nil),
        Genre(id: "ceo_billionaire", name: "CEO & Milyoner", iconURL: nil),
        Genre(id: "revenge", name: "İntikam", iconURL: nil),
        Genre(id: "werewolf_fantasy", name: "Kurt Adam & Fantastik", iconURL: nil),
        Genre(id: "family_drama", name: "Aile & Dram", iconURL: nil),
        Genre(id: "time_travel", name: "Zaman Yolculuğu", iconURL: nil),
        Genre(id: "hidden_identity", name: "Gizli Kimlik", iconURL: nil),
        Genre(id: "thriller", name: "Gerilim", iconURL: nil),
        Genre(id: "comedy", name: "Komedi", iconURL: nil),
        Genre(id: "historical", name: "Tarihi", iconURL: nil)
    ]
}
