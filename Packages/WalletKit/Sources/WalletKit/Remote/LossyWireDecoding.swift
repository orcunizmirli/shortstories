import Foundation

/// Diziyi ELEMAN BAZLI dayanıklı decode eder: present-but-invalid (bozuk) TEK bir eleman TÜM diziyi
/// (ve onu saran zarfı) düşürmez — yalnız o eleman ATLANIR, kalanı akar.
///
/// `decodeIfPresent` yalnız EKSİK/`null` ALANI korur; bir backend elemanının zorunlu alanı bozuk gelirse
/// (ör. `amount`/`balanceAfter` null, tarih parse edilemez) sentezlenen `[Element]` decode'u TÜM diziyi
/// throw eder → onu saran money-kritik zarf (unlock/verify 200'ü) veya ekran (Coin Mağazası) komple düşer
/// (wire-decode hunt HIGH/MEDIUM). ContentKit `LossyArray` deseninin WalletKit-yerel karşılığı (money
/// modülünü content modülüne bağlamadan; App `SkippableProgress` deseniyle aynı ruh).
private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            // `Skippable` HER ZAMAN başarıyla decode olur (dıştaki imleci bir eleman ilerletir); içteki
            // `Element` bozuksa `value == nil` → atlanır (imleç yine ilerlemiştir).
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
    /// `decodeIfPresent([Element].self)`in dayanıklı karşılığı: alan yok/`null`/yanlış-tip → `[]`; alan varsa
    /// eleman-bazlı lossy decode (bozuk elemanlar atlanır, kalan liste döner). Yalnız GÖSTERİM/liste alanları
    /// için — otoriter tekil alanlar (wallet snapshot, unlock record) strict kalır (fail-closed).
    func decodeLossyArray<Element: Decodable>(_: Element.Type, forKey key: Key) -> [Element] {
        // `try?` alan-yok/null (decodeIfPresent nil) VE yanlış-tip (unkeyedContainer throw) → nil'i düzler.
        guard let lossy = try? decodeIfPresent(LossyArray<Element>.self, forKey: key) else {
            return []
        }
        return lossy.elements
    }
}
