import CryptoKit
import Foundation

/// Backend `userId`'den deterministik `appAccountToken` (UUIDv5) üretir (06 §4.3): transaction'ı
/// ShortSeries hesabına bağlar; misafir → Apple/Google/e-posta bağlama sonrası aynı token korunur.
/// UUIDv5 = namespace UUID + ad'ın SHA-1'i (RFC 4122 §4.3). CryptoKit `Insecure.SHA1` yalnız
/// bu deterministik türetme için kullanılır (güvenlik sınırı değil).
public enum AppAccountToken {
    /// ShortSeries için sabit namespace UUID (rastgele üretilmiş, kalıcı).
    private static let namespace = UUID(uuidString: "8B0E9D2C-4F3A-5B6C-9D7E-1A2B3C4D5E6F")!

    public static func token(forUserID userID: String) -> UUID {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16 + userID.utf8.count)
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(userID.utf8))

        var digest = Array(Insecure.SHA1.hash(data: Data(bytes)).prefix(16))
        // Sürüm (5) ve variant bitlerini RFC 4122'ye göre ayarla.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80

        let uuidBytes = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: uuidBytes)
    }
}
