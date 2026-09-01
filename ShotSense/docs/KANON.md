# KANON — Değişmez Kurallar

Bu kurallar tartışmaya kapalıdır. Değiştirmek için ayrı bir karar kaydı (ADR) gerekir.

1. **Ağ yok.** Hiçbir pakette `URLSession`, `Network`, socket, üçüncü parti analitik/reklam/crash
   SDK'sı bulunmaz. CI denetler (R7). Bu ürünün tek gerçek savunma hattıdır.
2. **Asset yok.** Tüm ikonlar SF Symbols; tüm renkler `DesignSystem` token'ı. Görsel varlık dosyası
   eklenmez (App Icon hariç).
3. **Domain saftır.** `ShotCore` yalnız Foundation + `AppFoundation` import eder.
4. **Kompozisyon kökü tektir.** Adaptörler yalnız App target'ta bağlanır.
5. **LLM asla tek yol değildir.** Her zekâ özelliğinin heuristik karşılığı vardır; Apple
   Intelligence olmayan cihazda ürün eksiksiz çalışır (özet kalitesi düşer, akış kırılmaz).
6. **Grounding zorunlu.** OCR metninde bulunamayan hiçbir çıkarılmış değer kullanıcıya gösterilmez.
7. **Hassas veri loglanmaz.** `recognizedText`, şifre, IBAN, kod hiçbir log satırına girmez.
8. **Silme onaylıdır.** Uygulama kullanıcı onayı olmadan hiçbir fotoğrafı silmez.
9. **İzin just-in-time'dır.** Açılışta toplu izin istenmez; Photos izni değer gösterildikten sonra istenir.
10. **Portrait-locked, SwiftUI-only, Swift 6 strict concurrency.**
11. **Paywall ayda en fazla 3 kez** otomatik gösterilir; "Restore" her paywall'da bulunur.
12. **Erişilebilirlik P0'dır.** VoiceOver + Dynamic Type + 44pt hedef, "sonra yaparız" değildir.
