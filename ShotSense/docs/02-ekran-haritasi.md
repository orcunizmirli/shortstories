# 02 — Ekran Haritası ve Navigasyon

## 1. Navigasyon iskeleti

`TabView` (3 sekme) + tam ekran modaller. Portrait-locked (v1).

```
RootView
├── Tab "Kitaplık"    → LibraryView ──▶ ShotDetailView ──▶ ActionSheet(Hatırlatıcı/Takvim)
│                                   └─▶ ImageViewerView (zoom)
├── Tab "Ara"         → SearchView ───▶ ShotDetailView
└── Tab "Ayarlar"     → SettingsView ─▶ IndexingSettingsView
                                     ├▶ PrivacyView
                                     └▶ SubscriptionView
Modaller:
  OnboardingFlow  (ilk açılış)
  PaywallView     (limit aşımı / Pro özellik dokunuşu)
  CleanupView     (temizlik asistanı, P1)
```

## 2. Ekran ekran

### 2.1 OnboardingFlow (modal, 4 adım)
1. **Değer** — "4.000 screenshot'ın var. Hiçbiri telefonundan çıkmadan aranabilir olsun."
2. **Örnek** — `PHPicker` ile kullanıcı 3 screenshot seçer, canlı analiz gösterilir (**izin istemeden**).
3. **İzin** — sonuç görüldükten sonra tam Photos erişimi istenir. Reddedilirse ürün sınırlı modda çalışır.
4. **İndeksleme** — ilerleme çubuğu; arka planda devam edebilir, kullanıcı beklemez.

> Kanon: izin ekranı **asla ilk ekran değildir**. Önce değer, sonra izin.

### 2.2 LibraryView
- Üstte: yatay kategori çipleri (Tümü, Fiş, Bilet, Wifi, …) + sayaç.
- Gövde: `LazyVGrid` 3 sütun, thumbnail + kategori rozeti + tarih.
- Analiz sürüyorsa üstte ince ilerleme bandı ("1.240 / 4.012 analiz edildi").
- Boş durumlar: izin yok / screenshot yok / kategori boş — üçü ayrı metin.
- Sağ üst: seçim modu (çoklu → sil / koleksiyona ekle).

### 2.3 SearchView
- Arama alanı + "Doğal dilde sor" ipucu.
- Sorgu yazılırken: anlık BM25 sonuçları (yerel, senkron).
- Enter / 400 ms duraklama: LLM sorgu ayrıştırma + hibrit sıralama → sonuç listesi.
- Ayrıştırılan filtreler **görünür çip** olarak gösterilir ("kategori: fiş", "tarih: son 30 gün")
  ve tek dokunuşla kaldırılabilir → kullanıcı LLM'in ne anladığını görür (güven).
- Öneri satırları: son aramalar + "Yaklaşan tarihler" + "Wifi şifreleri".

### 2.4 ShotDetailView
- Üstte görsel (dokun → `ImageViewerView`).
- Başlık (LLM), kategori rozeti, tarih.
- **Özet** kartı (1–2 cümle).
- **Çıkarılan bilgiler** listesi: her satır bir varlık; sağında kopyala / aksiyon düğmesi.
  - Tarih satırı → "Hatırlatıcı kur", "Takvime ekle"
  - Tutar/satıcı → "Kopyala"
  - Wifi → "Şifreyi kopyala"
  - URL → "Aç"
- **Metin** bölümü (katlanabilir, tam OCR çıktısı, seçilebilir).
- Alt bar: Paylaş · Koleksiyona ekle · Sil · "Yanlış mı? Düzelt".

### 2.5 SettingsView
- Abonelik durumu (Free/Pro, yönet).
- İndeksleme: otomatik/manuel, yalnız şarjda, "Şimdi yeniden analiz et".
- Dil (OCR dilleri).
- Gizlilik: "Bu uygulama ağ isteği yapmaz" + `07-gizlilik.md` özeti.
- Veri: indeksi sıfırla (görseller silinmez), dışa aktar.
- Zekâ durumu: "Apple Intelligence: açık / bu cihazda desteklenmiyor (heuristik mod)".

### 2.6 PaywallView
Tetikleyiciler: (a) 200. screenshot sonrası kitaplık, (b) 11. arama, (c) 4. aksiyon,
(d) Pro özellik dokunuşu. Ayda **en fazla 3 kez** otomatik gösterilir (kanon).

## 3. Durum matrisi (her liste ekranı için zorunlu)

| Durum | Gösterim |
|---|---|
| İzin yok | Açıklama + "Ayarlar'ı aç" + "Elle ekle" |
| İzin var, veri yok | "Ekran görüntüsü bulunamadı" |
| İndeksleme sürüyor, sonuç yok | İskelet (skeleton) hücreler |
| Sonuç var | İçerik |
| Hata | Kısa neden + "Tekrar dene" |

## 4. Erişilebilirlik kuralları
- Tüm dokunma hedefleri ≥ 44×44 pt.
- Her thumbnail'in `accessibilityLabel`'ı = LLM başlığı + kategori + tarih.
- Dynamic Type XXL'de grid 3→2→1 sütuna düşer.
- Renk **tek başına** kategori taşıyıcısı değildir; her rozette ikon + metin vardır.
