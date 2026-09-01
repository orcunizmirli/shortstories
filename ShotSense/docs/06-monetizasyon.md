# 06 — Monetizasyon

## 1. Model

Freemium + otomatik yenilenen abonelik. **Tüketilebilir yok, jeton yok, reklam yok.**
Reklam bilinçli olarak dışarıda: ürünün tek satış argümanı gizlilik; reklam SDK'sı
(IDFA/ATT, ağ trafiği) bu argümanı teknik olarak çürütür.

## 2. Ürünler (StoreKit 2)

| Ürün ID | Tür | Fiyat (US) | Not |
|---|---|---|---|
| `com.shotsense.pro.yearly` | Auto-renewable, `pro` grubu | $19.99/yıl | 7 gün ücretsiz deneme (introductory offer) |
| `com.shotsense.pro.monthly` | Auto-renewable, `pro` grubu | $3.99/ay | Deneme yok |
| `com.shotsense.pro.lifetime` | Non-consumable | $49.99 | v1.1'de; abonelik direncine karşı |

Yıllık varsayılan seçili ve "%58 tasarruf" rozetiyle gösterilir (anchoring).

## 3. Free / Pro sınırları

| Yetenek | Free | Pro |
|---|---|---|
| İndekslenen screenshot | En yeni **200** | Sınırsız |
| Anahtar kelime araması | Sınırsız | Sınırsız |
| Doğal dil araması | **10 / ay** | Sınırsız |
| Aksiyon (hatırlatıcı/takvim/kişi) | **3 / ay** | Sınırsız |
| Otomatik koleksiyonlar | 3 kategori | Tümü |
| Temizlik asistanı | — | ✓ |
| Dışa aktarma | — | ✓ |
| Widget / Shortcuts | — | ✓ |

**Neden bu sınırlar:** Free kullanıcı ürünün *işe yaradığını* görmeli (arama çalışır, kategoriler
görünür) ama *ölçekte* kullanamamalı. 200 sınırı yeni screenshot'lar geldikçe eski değerli
sonuçların düşmesine yol açar → doğal, sinir bozucu olmayan yükseltme baskısı.

## 4. Yetkilendirme mimarisi

```
EntitlementProviding (port, ShotCore)
   └── StoreKitEntitlementProvider (PaywallKit)
        ├── Transaction.currentEntitlements akışı dinlenir (uygulama açılışında + canlı)
        ├── Transaction.updates görevi App yaşam döngüsü boyunca ÇALIŞIR (kaçan işlem olmaz)
        └── Sonuç: Entitlement { tier: .free|.pro, expiresAt: Date?, isInGracePeriod: Bool }
```

Kurallar:
- **Sunucu doğrulaması yok** (sunucu yok). `VerificationResult.verified` yeterlidir; StoreKit 2
  imza doğrulamasını cihazda yapar.
- Kotalar (`10 arama/ay`, `3 aksiyon/ay`) cihazda `QuotaLedger` içinde tutulur; takvim ayı
  başında sıfırlanır. Kurcalanabilir olduğu kabul edilir — bu kabul edilebilir bir risktir,
  çünkü alternatif (sunucu) tüm iş modelini bozar.
- **Grace period** ve **billing retry** durumunda Pro erişimi sürer (churn azaltır).
- `Transaction.updates` işlenmeden `finish()` çağrılmaz.

## 5. Paywall tetikleyicileri ve frekans kapağı

| Tetikleyici | Bağlam metni |
|---|---|
| 200 limitine ulaşıldı | "4.012 screenshot'ın var, 200'ü indekslendi. Hepsini aç." |
| 11. doğal dil araması | "Bu ay 10 akıllı aramanı kullandın." |
| 4. aksiyon | "Hatırlatıcıya çevirme hakkın doldu." |
| Pro özelliğe dokunma | Özelliğe özgü metin |

- Otomatik paywall **ayda en fazla 3 kez**; kullanıcı kapattıktan sonra ≥48 saat beklenir.
- Ayarlar'dan her zaman erişilebilir (kapak yok).
- "Satın alımları geri yükle" **her paywall'da görünür** (App Review zorunluluğu).

## 6. Birim ekonomi

Değişken maliyet ≈ **$0** (sunucu yok, LLM cihazda, depolama kullanıcının).

```
Yıllık abone geliri          $19.99
App Store komisyonu (%15*)   -$3.00
Net                           $16.99   → marj %85
* Small Business Program (<$1M/yıl). İlk yıl sonrası %30 → net $13.99, marj %70.
```

Sabit maliyet: Apple Developer Program $99/yıl. **Başabaş: 6 abone/yıl.**

## 7. Ölçüm (cihaz-içi, ağsız)

`AnalyticsKit` halka tamponunda tutulan ve **yalnız kullanıcı isterse** dışa aktarılan olaylar:
`paywall_shown(trigger)`, `paywall_dismissed`, `trial_started`, `purchase_completed(productID)`,
`purchase_failed(errorCode)`, `restore_completed`. Bu veriler cihazdan **otomatik çıkmaz**;
toplu ürün metriği için App Store Connect'in kendi raporları kullanılır.
