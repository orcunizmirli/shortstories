# Rakip Parite Gap Analizi + İmplement Planı

**Amaç:** ReelShort / DramaBox / ShortMax / NetShort gibi kategori liderlerine karşı **%100 özellik paritesi** hedefi (`00-genel-bakis.md` §156) doğrultusunda, mevcut kod tabanının (kod-doğrulanmış envanter) eksik yönlerini tespit edip önceliklendirilmiş bir implement planı sunar.

**Yöntem:** Kod-doğrulanmış özellik envanteri (her iddia kaynak dosyaya karşı çapraz-kontrol) × Jan-2026 rakip özellik bilgisi. "Kasıtlı Won't" (doc 01 §4) ve "prep-bekleyen" (gerçek SDK/sertifika/sunucu) kalemleri gap SAYILMAZ.

Durum tarihi: 2026-08-28

---

## Özet: Kod tabanı olgunluğu

Feature yüzeyi büyük ölçüde **kurulu ve sertleşmiş** (prototip değil): 41-bulgu adversarial audit (0 açık), ağır unit-test suiteleri (AppFoundation ~302, WalletKit ~284, PlayerKit ~248, ProfileKit ~160, RewardsKit ~125). Monetizasyon, retention iç-işi, keşif, player, kütüphane/hesap tam. Parite açıkları **dar** ama bazıları **yüksek büyüme-leveri**.

---

## Kategori-kategori gap tablosu

Öncelik = Etki (büyüme/parite) × (1/Efor) × (1/Risk) × Ürün-netliği. **İ**=implement önerilir (otonom-uygun), **Ü**=ürün-yönü kararı gerekir (kullanıcı önceliklendirmesi), **P**=prep/altyapı bekliyor, **✗**=kasıtlı Won't.

### Monetizasyon — büyük ölçüde TAM
| Gap | Öncelik | Not |
|-----|---------|-----|
| İşlem-geçmişi listesi (PAY-08) | İ (düşük) | Zaten F2 planlı; salt-okunur liste + pagination, mevcut wire deseni |
| Promo/redeem kod | Ü | Sunucu sözleşmesi + UI; iş kararı |
| Season-pass / bundle SKU | Ü | Ürün-fiyat kararı |
| Coin hediye/transfer | ✗ | Kasıtlı Won't (doc 01 §4) |

### Retention/Gamification — EN YÜKSEK LEVER BURADA
| Gap | Öncelik | Not |
|-----|---------|-----|
| **Referral/davet-arkadaş programı** | **Ü (YÜKSEK etki)** | Türün en güçlü büyüme leveri (ReelShort/DramaBox'ta çekirdek). YOK. Davet-kodu + "davet et → ikisi de coin". Sunucu-otoriter kredi + attribution gerektirir → **sunucu sözleşmesi + iş kararı**. Client soyutlama deseni (injectable port + mock) hazır kurulabilir. |
| **App Store puanlama istemi (RTG-01)** | **İ — KISMEN YAPILDI (2026-08-28)** | Core (policy+controller+port) + check-in tetiği + kill-switch UYGULANDI. Kaldı: bölüm-tamamlama tetiği (feed hot-path güvenli gözlem noktası), negatif-sinyal bastırma, analitik event. Bkz. docs/01 RTG-01. |
| Spin-wheel / lucky-draw / mystery-box | Ü | Yaygın rakip gamification; ekonomi-dengesi + sunucu kredi kararı |
| Piggy-bank (izledikçe coin biriktir) | Ü | ReelShort'ta var; ekonomi kararı |
| Leaderboard / rozet / achievement | Ü | Sosyal-retention; ürün kararı |

### Keşif — TAM (küçük F2 kalemleri)
| Gap | Öncelik | Not |
|-----|---------|-----|
| "Çünkü şunu izledin" / benzer-seri rafları (DSC-06) | Ü | F2 planlı; sunucu-öneri sözleşmesi |
| Yeni-bölüm yayın takvimi UI (DTL-05) | İ (orta) | F2; client-render, mevcut wire |

### Player — TAM; birkaç F1-skeleton doldurulmalı
| Gap | Öncelik | Not |
|-----|---------|-----|
| **Bölüm-listesi (BolumListesi) sheet** | **İ (orta)** | HomeCoordinator:262-271 F1-STUB. Dizinin bölüm ızgarası + kilit durumu + seek. Kanon Must; **gerçek client gap** |
| **Altyazı seçim sheet + AVMediaSelection render** | **İ (orta-yüksek)** | LOC-01 Must/F1 ama sheet stub + `AVMediaSelection` HİÇ yok. Altyazı tercihi/menüsü var, GERÇEK track seçimi/render yok. Gerçek gap |
| **Hız-seçim menüsü** | İ (düşük) | F1-STUB (hold-2x çalışıyor ama menü yok) |
| Thumbnail scrub önizleme (PLR-05) | Ü | F2 |
| Offline indirilenler | P | FairPlay DRM'e bağlı (F3, prep) |

### Kütüphane/Hesap — TAM
| Gap | Öncelik | Not |
|-----|---------|-----|
| Çoklu profil / kids-mode / parental PIN | Ü | Netflix-tarzı; ürün kararı |
| Avatar upload / kullanıcı-adı düzenleme | Ü | Profil-çekim portu (ProfilView:75 TODO) |

### Sosyal/Paylaşım
| Gap | Öncelik | Not |
|-----|---------|-----|
| Puan/yorum (SKStoreReview app-içi) | İ | RTG-01 ile örtüşür (yukarı) |
| Yorumlar / like / reaksiyon | ✗ | Kasıtlı Won't F1–F2 (doc 01 §4) |

### Lokalizasyon/Erişilebilirlik — ⚠️ TUTARSIZLIK
| Gap | Öncelik | Not |
|-----|---------|-----|
| **String Catalog (SS-160) — DOĞRULANDI: YOK** | **Ü (yüksek — büyük iş + base-dil kararı)** | `.xcstrings`/`.strings`/`.stringsdict` HİÇBİRİ yok; project.yml'de `knownRegions`/`developmentRegion`/localization bloğu yok (kod-doğrulandı 2026-08-28). SS-160 (docs/09:327, **F0** task) String Catalog altyapısı commit'li kodda GERÇEKTEN eksik — KANON/memory "hazır" der, YANLIŞ. UI `LocalizedStringKey` kullanıyor (doğru desen) ama katalog+knownRegions olmadan TR/ES/PT lokalize EDİLEMEZ. Tam migrasyon (her paketten literal→key çıkarımı + EN-kaynak re-keying + pseudo-locale build) BÜYÜK + base-dil kararı → otonom değil, **kullanıcı önceliği + karar gerekir**. Lansman öncesi kritik. |
| RTL / VoiceOver rotor / reduce-motion | Ü | Erişilebilirlik denetimi |

---

## Önerilen sıra (otonom-uygun, düşük-risk, parite-kapatıcı)

Bu kalemler **spec-dokümante gereksinim** (spekülatif rakip-özelliği değil), düşük-riskli, mevcut mimariye uygun — kullanıcı ürün-yönü kararı GEREKTİRMEZ:

1. **RTG-01 tamamla** (kaldı: bölüm-tamamlama tetiği + negatif-sinyal bastırma + analitik event). Kill-switch zaten var → güvenli.
2. **BolumListesi sheet** (player F1-stub doldur) — Must, gerçek gap, izleme-akışına değer.
3. **Altyazı seçim + AVMediaSelection** (LOC-01 Must) — daha büyük ama dokümante Must; çok-dilli katalog stratejisinin (00 §119 rakip farklılaştırıcı) client tarafı.

> **⚠️ KULLANICIYA SURFACE EDİLDİ (2026-08-28):** SS-160 String Catalog altyapısı (F0 task) commit'li kodda **YOK** — KANON/memory "hazır" diyor ama `.xcstrings`+knownRegions bulunmuyor. TR/ES/PT lokalizasyonun tüm önkoşulu. Tam migrasyon büyük + base-dil (EN vs TR kaynak) kararı içerir → otonom yapılMADI, kullanıcı kararı bekliyor.

## Ürün-yönü kararı gereken (kullanıcı önceliklendirmesi)

Bunlar **yüksek etkili ama ürün/ekonomi/sunucu-sözleşmesi kararları** — otonom implement edilMEZ, kullanıcı önceliği beklenir:

- **Referral/davet programı** (en yüksek büyüme leveri; sunucu-attribution + kredi ekonomisi).
- Spin-wheel / piggy-bank / leaderboard (gamification ekonomi-dengesi).
- Season-pass/bundle, promo kodları (fiyat-SKU kararı).
- Çoklu profil / parental controls (ürün kapsamı).

Client-soyutlama deseni (injectable port + mock; fraud/win-back/rewarded-ad/hesap-bağlamada kanıtlı) bunların HEPSİ için hazır — karar gelince gerçek sözleşme ince adaptörle takılır.
