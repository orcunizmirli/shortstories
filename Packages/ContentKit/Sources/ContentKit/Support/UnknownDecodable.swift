/// Zorunlu decoding kalıbı (05 §12 kural 4): bilinmeyen enum değeri ASLA decode hatası
/// üretmez, `.unknown`a düşer. `.unknown`a düşen kayıtların varsayılan davranışları:
/// `FeedItem.type == .unknown` → item atlanır; `EpisodeAccess.kind == .unknown` →
/// kilitli varsayılır (güvenli taraf) ve authorize gerçek durumu çözer.
///
/// Not: Kanonik tanım 05-veri-modeli-api.md'dedir; başka bir paket (WalletKit vd.)
/// ihtiyaç duyduğunda AppFoundation'a taşınması kırıcı olmayan bir refactor'dur.
public protocol UnknownDecodable: RawRepresentable, CaseIterable where RawValue == String {
    static var unknown: Self { get }
}

public extension UnknownDecodable where Self: Decodable {
    /// Yalnız bilinmeyen string DEĞİL, null ya da string-olmayan değer (sayı, obje…)
    /// de decode hatası üretmez — hepsi `.unknown`a düşer (05 §12 kural 4'ün sınır hali).
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self)
        else {
            self = .unknown
            return
        }
        self = Self(rawValue: raw) ?? .unknown
    }
}
