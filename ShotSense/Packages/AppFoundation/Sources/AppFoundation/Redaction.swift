import Foundation

/// Hassas değerleri kullanıcıya gösterirken ve log/dışa aktarma yollarında maskeler.
///
/// KANON §7 gereği bu tip, hassas varlıkların (şifre, IBAN, doğrulama kodu) tek maskeleme
/// noktasıdır — ekranlar kendi maskeleme mantığını yazmaz.
public enum Redaction {
    /// Değeri son `visibleSuffix` karakteri açıkta kalacak biçimde maskeler.
    ///
    /// Maske uzunluğu **kaynak uzunluğu sızdırmaz**: kaç karakter olursa olsun sabit 4 nokta
    /// kullanılır, aksi hâlde bir şifrenin uzunluğu ekrandan okunabilir olurdu.
    public static func mask(_ value: String, visibleSuffix: Int = 0) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard visibleSuffix > 0, trimmed.count > visibleSuffix else { return "••••" }
        return "•••• " + String(trimmed.suffix(visibleSuffix))
    }

    /// Serbest metni loglanabilir hâle getirir: yalnızca uzunluk ve karakter sınıfı bilgisi kalır.
    public static func summarize(_ value: String) -> String {
        let hasDigits = value.contains { $0.isNumber }
        let hasLetters = value.contains { $0.isLetter }
        return "<len=\(value.count) digits=\(hasDigits) letters=\(hasLetters)>"
    }
}
