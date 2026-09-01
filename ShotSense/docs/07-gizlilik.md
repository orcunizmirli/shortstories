# 07 — Gizlilik, İzinler, App Review

## 1. Taahhüt

> **Hiçbir görsel, hiçbir OCR metni, hiçbir analiz sonucu cihazdan çıkmaz.**

Bu bir pazarlama cümlesi değil, **mimari kısıttır** ve CI'da denetlenir
(`03-mimari.md` R7: hiçbir pakette `URLSession`/`Network`/socket API'si yoktur).

## 2. İstenen izinler

| İzin | Ne zaman | Info.plist anahtarı | Reddedilirse |
|---|---|---|---|
| Fotoğraflar (okuma) | Onboarding 3. adım, **değer gösterildikten sonra** | `NSPhotoLibraryUsageDescription` | `PHPicker` ile elle ekleme çalışır |
| Fotoğraflar (silme) | Yalnız temizlik asistanı kullanılırsa | `NSPhotoLibraryAddUsageDescription` | Temizlik kapalı |
| Hatırlatıcılar | Kullanıcı "Hatırlatıcı kur"a bastığında | `NSRemindersFullAccessUsageDescription` | Aksiyon kapalı, metin kopyalanabilir |
| Takvim | Kullanıcı "Takvime ekle"ye bastığında | `NSCalendarsWriteOnlyAccessUsageDescription` | Aynı |
| Kişiler (P1) | "Kişi olarak kaydet" | `NSContactsUsageDescription` | Aynı |

**İstenmeyen izinler:** konum, mikrofon, kamera, bildirim (v1'de yok), ağ.

Her izin **kullanım anında** (just-in-time) istenir. Uygulama açılışında toplu izin isteme yok.

## 3. App Privacy (App Store Connect beyanı)

| Kategori | Beyan |
|---|---|
| Data Used to Track You | **Yok** |
| Data Linked to You | **Yok** |
| Data Not Linked to You | **Yok** |

Yani "Data Not Collected". Bu beyanın doğru kalması için: analitik SDK yok, crash SDK yok
(Xcode Organizer'ın Apple tarafı raporları kullanılır), reklam SDK yok.

## 4. Hassas veri işleme

Ekran görüntüleri **doğaları gereği** şifre, IBAN, kimlik numarası içerir. Kurallar:

- `wifiPassword`, `code`, `iban` türü varlıklar UI'da **varsayılan olarak maskelenir**
  (`•••• 1234`), dokununca açılır.
- Bu varlıklar hiçbir log satırına yazılmaz. `AppFoundation.Log` içinde
  `redact(_:)` zorunludur; ham `recognizedText` **asla** loglanmaz.
- Panoya kopyalamada hassas alanlar için `UIPasteboard.setItems(_:options:)` ile
  `.expirationDate` = +60 sn kullanılır.
- Ekran görüntüsü içeriği hiçbir zaman `UserDefaults`'a yazılmaz (yedeklemeye girer).
- SwiftData deposu `.complete` dosya koruma sınıfıyla açılır (cihaz kilitliyken okunamaz).

## 5. App Review riskleri ve hazırlık

| Risk | Hazırlık |
|---|---|
| "Neden tam fotoğraf erişimi?" | Review notunda: "Uygulama ekran görüntüsü kitaplığını cihaz üstünde indeksler; hiçbir veri gönderilmez. Sınırlı erişim de desteklenir ama kitaplık genelinde arama sağlamaz." |
| Guideline 2.1 — demo hesabı | Gerekmez (hesap yok). Review'a örnek screenshot seti içeren ekran kaydı eklenir. |
| Guideline 3.1.1 — abonelik | Paywall'da fiyat, periyot, otomatik yenileme metni, EULA + gizlilik linkleri; "Restore" düğmesi. |
| Foundation Models desteklemeyen review cihazı | Heuristik mod tam çalışır; "Apple Intelligence gerekli" mesajı **hiçbir yerde blokaj değildir**. |
| Guideline 5.1.1 — izin metni | Her `UsageDescription` ne için kullanıldığını somut anlatır. |

## 6. Kullanıcıya sunulan kontroller

- **İndeksi sıfırla** — tüm türev veriyi siler, görselleri korur.
- **Dışa aktar** — kendi verisini JSON olarak alır (veri taşınabilirliği).
- **Zekâ modunu kapat** — yalnız OCR + heuristik, LLM hiç çalışmaz.
- Ayarlar > Gizlilik ekranında bu belgenin özeti ve "ağ isteği yapılmadı" ifadesi.
