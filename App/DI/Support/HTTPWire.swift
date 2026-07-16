import Foundation

extension String {
    /// Path segmenti yüzde-kaçlama (App-yerel; ContentKit'in modül-içi aynı yardımcısını import
    /// etmeden). Sunucu ID'leri path'e HAM interpolasyonla girmez: izinli küme `urlPathAllowed` EKSİ
    /// "/" — böylece "a/b" gibi bir ID "a%2Fb" olur ve path hiyerarşisini bozamaz.
    var pathSegmentEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// Gövdesiz/içerik-yok yanıtların `Decodable` yer tutucusu. `PUT/DELETE /me/favorites/{id}` (`{}`)
/// ve `POST /playback/progress` (`{ "merged": [...] }`, göz ardı edilen) gibi uçlar için kullanılır.
/// `APIClient.send` yanıtı yine `E.Response`e decode ettiğinden `init(from:)` gelen İÇERİĞİ (keyed
/// obje, dizi, `null` — herhangi bir GEÇERLİ JSON) container'a hiç bakmadan YOK SAYAR ve başarır.
///
/// SINIR — gerçek-boş gövde (`""`, 204 No-Content): `JSONDecoder` boş `Data`yı `init(from:)` ÇAĞRILMADAN
/// ÖNCE ayrıştırır ve "Unexpected end of file" ile ÇÖKER; bu tip bunu kurtaramaz (parse init'ten önce
/// olur). Şu an hiçbir uç gerçek-boş 204 döndürmüyor (favorites/progress JSON `{}`/`{merged}` döner),
/// dolayısıyla bug latenttir. Kalıcı düzeltme çağırandadır ve AppFoundation'ı gerektirir:
/// TODO(AppFoundation, kapsam-dışı — App yalnız yazılabilir): `APIClient.performOnce` decode'dan ÖNCE
/// 204/boş-gövde kısa-devresi yapmalı — `if data.isEmpty, let empty = EmptyResponse() as? E.Response {
/// return empty }` — böylece gerçek-boş 204 decode-hatası (`.network(.decoding)`) olmadan başarır.
struct EmptyResponse: Decodable, Sendable {
    init() {}

    init(from _: any Decoder) throws {}
}
