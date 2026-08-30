import Foundation

/// Diziyi ELEMAN BAZLI dayanıklı decode eder: present-but-invalid (bozuk) TEK bir eleman TÜM diziyi
/// (ve dolayısıyla tüm sayfa/ekran zarfını) düşürmez — yalnız o eleman ATLANIR, kalanı akar.
///
/// `decodeIfPresent` yalnız EKSİK/`null` alanı korur; bir backend elemanının zorunlu alanı bozuk
/// gelirse (`imageURL` geçersiz, `id` eksik, tarih parse edilemez) sentezlenen `[Element]` decode'u
/// TÜM diziyi throw eder ve Keşfet/Feed komple boşalır (audit MEDIUM/LOW: decode-robustness). Bu tip
/// her elemanı ayrı, "atlanabilir" bir sarmalayıcıda decode eder → bozuk eleman sessizce düşer.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            // `Skippable` HER ZAMAN başarıyla decode olur (dıştaki container imlecini bir eleman
            // ilerletir); içteki `Element` bozuksa `value == nil` → atlanır (imleç yine ilerlemiştir).
            let wrapped = try container.decode(Skippable.self)
            if let value = wrapped.value {
                result.append(value)
            }
        }
        elements = result
    }

    private struct Skippable: Decodable {
        let value: Element?

        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent([Element].self)`in dayanıklı karşılığı: alan yok/`null` → `[]`; alan varsa
    /// eleman-bazlı lossy decode (bozuk elemanlar atlanır, kalan liste döner).
    func decodeLossyArray<Element: Decodable>(
        _: Element.Type,
        forKey key: Key
    ) throws -> [Element] {
        try decodeIfPresent(LossyArray<Element>.self, forKey: key)?.elements ?? []
    }

    /// Opak sayfalama cursor'ını decode eder; boş/boşluk-yalnızca string'i (geçerli bir opak cursor
    /// DEĞİL) nil'e normalize eder → `Page.isLastPage` (nextCursor == nil) doğru son-sayfayı türetir ve
    /// `cursor=""` ile aynı sayfanın tekrar istendiği sonsuz/yinelenen sayfalama önlenir (savunmacı sınır).
    func decodeOpaqueCursor(forKey key: Key) throws -> String? {
        let raw = try decodeIfPresent(String.self, forKey: key)
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }
}
