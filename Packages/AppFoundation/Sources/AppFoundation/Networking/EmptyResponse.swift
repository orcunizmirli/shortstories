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
    /// 204/boş-gövde sözleşmesi: boş yanıt gövdesini `init(from:)` çağırmadan (sahte EOF hatası
    /// üretmeden) çözer. `EmptyResponse` doğrudan üretilir; tüm alanları opsiyonel olan (boştan
    /// decode edilebilen) tipler `{}` üzerinden çözülür. Gövde GEREKTİREN bir tipe boş gövde
    /// gelirse `nil` döner — çağıran bunu gerçek bir decoding hatası olarak ele alır.
    func decodeEmptyBody<T: Decodable>(as type: T.Type) -> T? {
        if let empty = EmptyResponse() as? T {
            return empty
        }
        return try? decode(type, from: Data("{}".utf8))
    }
}
