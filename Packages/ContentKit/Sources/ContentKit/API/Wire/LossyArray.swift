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
    /// Decode-aşamasında ATLANAN (present-but-invalid) eleman sayısı — "sessiz kayıp yok" invariantı için
    /// `Page.droppedItemCount`e taşınır (audit: decode-aşaması düşüşleri telemetriye görünmez kalmasın).
    let droppedCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        var dropped = 0
        result.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            // `Skippable` HER ZAMAN başarıyla decode olur (dıştaki container imlecini bir eleman
            // ilerletir); içteki `Element` bozuksa `value == nil` → atlanır (imleç yine ilerlemiştir).
            let wrapped = try container.decode(Skippable.self)
            if let value = wrapped.value {
                result.append(value)
            } else {
                dropped += 1
            }
        }
        elements = result
        droppedCount = dropped
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
        decodeLossyArrayCounting(Element.self, forKey: key).elements
    }

    /// Lossy decode + decode-aşamasında ATLANAN eleman sayısı (droppedItemCount telemetrisi — sessiz kayıp yok).
    /// Ayrıca alan var ama ARRAY DEĞİLSE (obj/string; sunucu/proxy bug) `unkeyedContainer` throw'unu yutup
    /// `([],0)` döner → TÜM zarf/ekran düşmez (savunmacı, audit LOW: yanlış-tip alan tüm objeyi düşürüyordu).
    func decodeLossyArrayCounting<Element: Decodable>(
        _: Element.Type,
        forKey key: Key
    ) -> (elements: [Element], dropped: Int) {
        // `try?` LossyArray??'yi düzleştirir: alan yok/null (decodeIfPresent nil) VE yanlış-tip (init throw) → nil.
        guard let lossy = try? decodeIfPresent(LossyArray<Element>.self, forKey: key) else {
            return ([], 0)
        }
        return (lossy.elements, lossy.droppedCount)
    }

    /// Non-core tarih alanı (cache metadata / UI etiketi): eksik/`null`/BOZUK (parse edilemez) → `nil`.
    /// `decodeIfPresent` yalnız eksik/null'ı korur; present-but-malformed tarih tüm objeyi düşürmesin diye
    /// parse hatası da yutulur (audit: non-core tarih strict decode geçerli seri/bölümü full-screen ederdi).
    func decodeLossyDate(forKey key: Key) -> Date? {
        try? decodeIfPresent(Date.self, forKey: key)
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
