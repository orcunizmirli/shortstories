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

// `EmptyResponse` artık App-yerel DEĞİL: AppFoundation `Networking/EmptyResponse.swift`'te public
// tanımlıdır ve `APIClient`/`MockAPIClient` boş 2xx gövdesini (`""`, 204 No-Content) decode-öncesi
// kısa-devre ile güvenle çözer (`decodeEmptyBody` → `init(from:)` çağrılmaz; sahte "Unexpected end of
// file" ORTADAN KALKAR). Gövdesiz uçlar (`PUT/DELETE /me/favorites/{id}` → `{}`, `POST /playback/
// progress` → `{ "merged": [...] }`, analitik batch → 204) `typealias Response = EmptyResponse` ile
// bu tek public tipi kullanır; non-empty geçerli JSON gövde de (boş struct sentez-decode'u her JSON'ı
// kabul eder) içerik okunmadan başarır. App'in eski gölge-tipi + "bare 204 latent bug" TODO'su artık
// gereksizdir (adaptörler bare 204'ü hataya çevirmez).
