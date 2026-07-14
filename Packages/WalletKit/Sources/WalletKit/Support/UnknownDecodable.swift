/// Bilinmeyen enum değerlerine dayanıklı decoding (05 §12 kural 4): sunucu yeni bir enum
/// değeri eklerse istemci decode hatası ÜRETMEZ, `.unknown`a düşer. Kanonik tanım
/// `AppFoundation`/`ContentKit`'te yaşar; WalletKit ContentKit'i çekemediği için (R3) aynı
/// sözleşmeyi burada yerel olarak taşır — taşıma tek yön bağımlılık kuralını korur.
public protocol UnknownDecodable: RawRepresentable, CaseIterable where RawValue == String {
    static var unknown: Self { get }
}

public extension UnknownDecodable where Self: Decodable {
    /// Yalnız bilinmeyen string değil; null / string-olmayan değer de `.unknown`a düşer.
    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self)
        else {
            self = .unknown
            return
        }
        self = Self(rawValue: raw) ?? .unknown
    }
}
