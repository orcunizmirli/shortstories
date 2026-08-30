import Foundation

/// Gövdesiz başarı yanıtı için işaretçi tip (05 §4.2.1/§8: `POST /auth/email/start`,
/// `POST /auth/email/password`, analitik batch — hepsi `204 No Content`). Gövde-taşımayan
/// uçlar `typealias Response = EmptyResponse` kullanır; `APIClient` boş gövdede `init(from:)`
/// çağırmadan doğrudan bir örnek döndürür (JSONDecoder boş `Data`'da sahte "Unexpected end of
/// file" fırlatır — bu tip o sahte hatayı ortadan kaldırır).
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}

public extension JSONDecoder {
    /// 204/boş-gövde sözleşmesi: boş yanıt gövdesini YALNIZ gerçek gövdesiz uçlar (`EmptyResponse`) için
    /// `init(from:)` çağırmadan (sahte EOF hatası üretmeden) çözer. İÇERİK tipleri (tüm alanları opsiyonel
    /// olsalar bile) boş gövdede `nil` döner → çağıran bunu gerçek decoding hatası sayar. Aksi halde bir
    /// içerik ucuna 200 + boş gövde (CDN truncation/bozuk-cache) gelince `{}` fallback'i sessizce all-nil
    /// değer üretip "boş son sayfa" (yarım feed "bitti") sanılmasına yol açardı (audit LOW).
    func decodeEmptyBody<T: Decodable>(as _: T.Type) -> T? {
        EmptyResponse() as? T
    }
}
