import Foundation
import ShotCore

/// Kalite ölçümünün altın kümesi (04 §7).
///
/// Her giriş gerçek bir ekran görüntüsünden alınmış OCR metnini temsil eder. Küme CI'da
/// `HeuristicAnalyzer` doğruluğunu ölçer ve eşiğin altına düşerse build'i kırar — sözlük
/// ağırlıklarında yapılan bir "iyileştirme" başka kategorileri bozarsa hemen görülür.
///
/// TODO(SS-015): küme 60 örneğe çıkarılacak; her kategoriden en az 4 örnek hedefleniyor.
enum GoldenCorpus {
    struct Entry {
        let name: String
        let text: String
        let expectedCategory: ShotCategory
        /// Bu metinden çıkarılması beklenen varlık türleri.
        let expectedEntityKinds: Set<EntityKind>
    }

    /// Metni satırlara bölerek sahte bir OCR belgesi üretir; üstteki satır başlık kabul edilir.
    static func document(for entry: Entry) -> RecognizedDocument {
        let lines = entry.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let blocks = lines.enumerated().map { index, line in
            RecognizedDocument.TextBlock(
                text: line,
                verticalPosition: 0.08 + Double(index) * 0.05,
                relativeHeight: index == 0 ? 0.035 : 0.02,
                confidence: 0.95
            )
        }
        return RecognizedDocument(blocks: blocks, languages: ["tr-TR"])
    }

    static let entries: [Entry] = [
        Entry(
            name: "market fişi",
            text: """
            MİGROS TİCARET A.Ş.
            FİŞ NO: 0042
            ARA TOPLAM 249,90 TL
            KDV %20 41,65 TL
            TOPLAM 291,55 TL
            """,
            expectedCategory: .receipt,
            expectedEntityKinds: [.amount]
        ),
        Entry(
            name: "ingilizce fiş",
            text: """
            Order Summary
            SUBTOTAL $24.99
            TAX $2.00
            TOTAL $26.99
            """,
            expectedCategory: .receipt,
            expectedEntityKinds: [.amount]
        ),
        Entry(
            name: "biniş kartı",
            text: """
            BİNİŞ KARTI
            Yolcu: AHMET YILMAZ
            Uçuş: TK 1982
            Kalkış: IST 14:35
            Koltuk: 12A
            """,
            expectedCategory: .ticket,
            expectedEntityKinds: [.flightNumber]
        ),
        Entry(
            name: "otel wifi",
            text: """
            Wi-Fi Ağı
            SSID: OtelMisafir
            Şifre: Deniz2026!
            """,
            expectedCategory: .wifi,
            expectedEntityKinds: [.wifiPassword]
        ),
        Entry(
            name: "banka ekranı",
            text: """
            Hesap Bakiyesi
            IBAN: TR33 0006 1005 1978 6457 8413 26
            Bakiye: 12.450,00 TL
            """,
            expectedCategory: .banking,
            expectedEntityKinds: [.iban, .amount]
        ),
        Entry(
            name: "kargo takibi",
            text: """
            Kargonuz dağıtımda
            Takip No: 1Z999AA10123456784
            Teslimat: bugün 18:00'e kadar
            """,
            expectedCategory: .shipping,
            expectedEntityKinds: [.trackingNumber]
        ),
        Entry(
            name: "yemek tarifi",
            text: """
            Mercimek Çorbası
            Malzemeler
            2 su bardağı kırmızı mercimek
            1 çay kaşığı tuz
            Hazırlanışı
            """,
            expectedCategory: .recipe,
            expectedEntityKinds: []
        ),
        Entry(
            name: "python hatası",
            text: """
            Traceback (most recent call last):
            File "main.py", line 12
            TypeError: undefined is not a function
            """,
            expectedCategory: .code,
            expectedEntityKinds: []
        ),
        Entry(
            name: "toplantı daveti",
            text: """
            Toplantı Daveti
            Tarih: 14 Şubat 2026 saat 10:00
            Katılımcılar: 4 kişi
            """,
            expectedCategory: .event,
            expectedEntityKinds: []
        ),
        Entry(
            name: "ürün sayfası",
            text: """
            Kablosuz Kulaklık
            Sepete Ekle
            ₺1.299,00
            Stokta var
            4.7 puan · 2.341 yorum
            """,
            expectedCategory: .product,
            expectedEntityKinds: [.amount]
        ),
        Entry(
            name: "yol tarifi",
            text: """
            Yol tarifi
            Bağdat Caddesi No:120
            12 dakika · 4,3 km
            """,
            expectedCategory: .location,
            expectedEntityKinds: []
        ),
        Entry(
            name: "sohbet",
            text: """
            Ahmet
            son görülme bugün 14:20
            yazıyor...
            """,
            expectedCategory: .conversation,
            expectedEntityKinds: []
        ),
        Entry(
            name: "makale",
            text: """
            Yapay Zekâ ve Gizlilik
            5 dakika okuma
            Yazar: Elif Demir
            Yayınlandı: 3 Ocak 2026
            """,
            expectedCategory: .article,
            expectedEntityKinds: []
        ),
        Entry(
            name: "kimlik kartı",
            text: """
            T.C. Kimlik Kartı
            Seri No: A01B23456
            Doğum Tarihi: 01.01.1990
            """,
            expectedCategory: .identity,
            expectedEntityKinds: []
        ),
        Entry(
            name: "ingilizce kargo",
            text: """
            Your package is out for delivery
            Tracking: 1Z999AA10123456784
            Courier: UPS
            """,
            expectedCategory: .shipping,
            expectedEntityKinds: [.trackingNumber]
        ),
        Entry(
            name: "oyun ekranı",
            text: """
            LEVEL 42
            READY
            """,
            expectedCategory: .other,
            expectedEntityKinds: []
        ),
        Entry(
            name: "doğrulama kodu mesajı",
            text: """
            Doğrulama kodu: 482913
            Bu kodu kimseyle paylaşmayın.
            """,
            expectedCategory: .other,
            expectedEntityKinds: [.code]
        ),
        Entry(
            name: "ingilizce toplantı",
            text: """
            Team Sync
            Meeting · Calendar
            Attendees: 6
            """,
            expectedCategory: .event,
            expectedEntityKinds: []
        ),
    ]
}
