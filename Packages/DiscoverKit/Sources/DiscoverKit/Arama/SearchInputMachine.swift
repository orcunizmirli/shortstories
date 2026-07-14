import Foundation

/// Arama giriş debounce durum makinesi — SAF (02 §4.11). Zaman/ağ İÇERMEZ: yalnız girdi
/// olaylarından "ne yapılmalı" kararını ve yarış (race) tekilleştirmesi için monoton token'ı
/// üretir. Debounce zamanlaması ve ağ çağrısı AramaModel'dedir; bu tip yalnız kararı verir.
///
/// - min 2 karakter altı / boş → varsayılan (son + popüler aramalar) moduna (02 §4.11).
/// - ≥2 karakter → debounce sonrası öneri isteği planlanır.
/// - her girdi/gönderim `token`ı artırır; öneri yanıtı döndüğünde `isCurrent(token)` ile
///   yalnız EN GÜNCEL sorgunun yanıtı uygulanır (sıra-dışı yanıt savunması, §4.11 edge case).
/// - yapıştırılan uzun metin 100 karakterde kırpılır (§4.11 edge case).
public struct SearchInputMachine: Equatable, Sendable {
    /// Otomatik tamamlama minimum uzunluğu (02 §4.11 / 01 `DSC-03`).
    public static let minSuggestLength = 2
    /// Yapıştırma kırpma sınırı (02 §4.11 edge case).
    public static let maxQueryLength = 100

    /// Monoton artan güncellik damgası. Her girdi/gönderim artırır.
    public private(set) var token = 0

    public init() {}

    /// Baştaki/sondaki boşlukları atar, 100 karaktere kırpar (paste guard).
    public static func normalize(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQueryLength))
    }

    /// Yazarken debounce kararı.
    public enum InputAction: Equatable, Sendable {
        /// Varsayılan moda dön (son + popüler aramalar); öneriler temizlenir.
        case browse
        /// `token` ile öneri isteği planla (debounce çağırında uygulanır).
        case scheduleSuggest(query: String, token: Int)
    }

    /// Gönderim (Enter/"Ara"/çip) kararı.
    public enum SubmitAction: Equatable, Sendable {
        case ignore
        case showResults(query: String, token: Int)
    }

    /// Metin değişimi → debounce kararı. Her çağrı token'ı artırır (askıdaki öneriyi geçersizler).
    public mutating func onInput(_ raw: String) -> InputAction {
        token += 1
        let query = Self.normalize(raw)
        if query.count < Self.minSuggestLength {
            return .browse
        }
        return .scheduleSuggest(query: query, token: token)
    }

    /// Gönderim → sonuç modu. Boş sorgu yok sayılır; aksi halde sonuç ızgarası (min 1 karakter —
    /// öneri eşiğinden bağımsız: kullanıcı doğrudan "Ara" derse tek harfli sonuç da açılabilir).
    public mutating func onSubmit(_ raw: String) -> SubmitAction {
        token += 1
        let query = Self.normalize(raw)
        guard !query.isEmpty else { return .ignore }
        return .showResults(query: query, token: token)
    }

    /// Verilen token en güncel mi (öneri/sonuç yanıtı uygulanmalı mı — yarış savunması).
    public func isCurrent(_ candidateToken: Int) -> Bool {
        candidateToken == token
    }
}
