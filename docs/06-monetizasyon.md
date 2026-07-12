# Monetizasyon — Coin Ekonomisi, IAP ve Paywall

**Amaç:** Bu doküman ShortSeries iOS istemcisinin gelir modelini uçtan uca tanımlar: coin ekonomisinin tasarımı, IAP kataloğu ve product ID şeması, StoreKit 2 implementasyonu, server tarafı cüzdan/doğrulama beklentileri, `UnlockSheet` / `CoinMagazasi` / `VIPAbonelik` ekranlarının UX spesifikasyonları, rewarded ads entegrasyonu (Faz 2), fiyatlandırma deneyleri planı ve App Store Review uyumluluğu. Geliştirme ekibinin `WalletKit` ve `RewardsKit` modüllerini bu spesifikasyona göre doğrudan implemente etmesi hedeflenir.

**İlgili dokümanlar:** 00-genel-bakis.md (iş modeli özeti), 01-ozellik-envanteri.md (F1/F2 kapsamı), 02-ekran-haritasi-navigasyon.md (UnlockSheet/CoinMagazasi/VIPAbonelik navigasyon akışları), 03-mimari.md (WalletKit modülü, `WalletStore` actor, DI), 04-player-engine.md (kilitli bölümde player davranışı), 05-veri-modeli-api.md (cüzdan/unlock API sözleşmeleri, `unlockPrice`), 07-retention-gamification.md (check-in ve görevlerle coin kazanımı), 08-analitik-deney.md (monetizasyon event'leri ve A/B deneyleri), 09-yol-haritasi-tasklar.md (fazlama), 10-arastirma-raporu.md (rakip benchmark kaynakları).

---

## 1. Gelir modeli genel bakış

### 1.1 Üç gelir kolonu

ShortSeries, kategori liderleriyle (ReelShort, DramaBox, NetShort, DramaWave) özellik paritesini hedefleyen üç katmanlı bir gelir modeli kullanır:

| Kolon | Mekanik | StoreKit tipi | Faz |
|---|---|---|---|
| **Coin (mikro-ödeme)** | Kilitli bölüm başına 50–100 coin harcanır; coin paketler halinde satılır | Consumable IAP | Faz 1 |
| **VIP abonelik** | Tüm bölümler açık + günlük bonus coin + reklamsız deneyim | Auto-renewable subscription | Faz 1 |
| **Rewarded ads** | Reklam izleyerek bölüm kilidi açma / coin kazanma; ödeme yapmayan kullanıcıyı monetize eder ve dönüşüm hunisi görevi görür | AdMob (birincil aday) | Faz 2 |

Erişim modeli: **dizi başına ilk 5–10 bölüm ücretsizdir (~ilk 10 dakika)**, sonrası bölüm başına kilitlidir. Kilit, cliffhanger noktasına denk gelir; hangi bölümden itibaren kilitleneceğini ve bölüm fiyatını içerik ekibi belirler, istemci bu bilgiyi API'den okur (`unlockPrice`, bkz. 05-veri-modeli-api.md). İstemcide hiçbir kilit eşiği veya fiyat hardcode edilmez.

### 1.2 Rakip benchmark özeti

Kategorinin doğrulanmış pazar verileri (Sensor Tower/InvestGame kaynaklı, ayrıntı 10-arastirma-raporu.md):

- Kategori Q1 2025'te ~$700M IAP geliri üretti (YoY ~4x), >370M indirme; 2024 başından kümülatif ~$2.3B.
- ReelShort: $130M Q1 2025, ~$490M kümülatif. DramaBox: $120M Q1 2025, ~$450M kümülatif. İkisi birlikte küresel short-drama IAP'ının ~%70'i.
- ABD kategori gelirinin ~%49'unu üretiyor (Q1 2025); hedef demografi ağırlıkla 25–45 yaş kadın.
- DramaWave Q1 2025'te indirmede 10x büyüme, 53M kümülatif indirme, ~$47M gelir; NetShort %171 çeyreklik gelir büyümesi, ~$57M kümülatif.

Rakip fiyatlandırma benchmark'ı:

| Uygulama | Model | Bilinen fiyat noktaları | Güvenilirlik |
|---|---|---|---|
| ReelShort | Coin ağırlıklı | Haftalık VIP kaynaklarda **$5.99–$20 aralığında ÇELİŞKİLİ** raporlanıyor; bölüm ~18–100 coin; seri tamamlama ~$10–50 | Fiyatlar tutarsız — yalnız aralık olarak kullan |
| DramaBox | Abonelik ağırlıklı | $3.99 intro / $5.99 haftalık / $49.99 yıllık; daha fazla ücretsiz bölüm | Doğrulanmış |
| DramaWave | VIP + tek seferlik | Haftalık/aylık VIP ~$19.90 + $9.99 tek seferlik teklif | Tek kaynak — temkinli kullan |

> **Uyarı:** Rakip fiyat ayrıntıları kaynaklar arasında tutarsızdır. Bu tablo yön göstericidir; **lansman öncesi güncel App Store fiyatları App Store'dan bizzat doğrulanmalıdır** (her rakip için storefront gezintisi + IAP listesi kontrolü). Bu doğrulama 09-yol-haritasi-tasklar.md'de lansman öncesi görev olarak yer alır.

### 1.3 ShortSeries hedefleri

- Ödeme dönüşümü (payer conversion) ≥ %3.
- Retention hedefleri (monetizasyonun bağımlı olduğu üst huni): D1 ≥ %30, D7 ≥ %10, D30 ≥ %5 (bkz. 07-retention-gamification.md).
- Rewarded engagement kullanıcılarının kategoride ~3x daha sık geri döndüğü (adjoe) verisi, rewarded ads'in yalnız gelir değil retention aracı olarak da tasarlanmasını gerektirir.

---

## 2. Coin ekonomisi tasarımı

### 2.1 Temel birim ve bölüm kilidi

- **Bölüm kilidi: 50–100 coin.** Değer API'den dinamik gelir (`unlockPrice`); dizi, bölüm ve deney koluna göre değişebilir. İstemci hiçbir zaman varsayılan fiyat üretmez; `unlockPrice` yoksa bölüm kilitli kabul edilir ve unlock butonu devre dışı kalır (hata durumu, bkz. §6.6).
- Referans oran (yalnız iç ekonomi hesabı için, kullanıcıya asla gösterilmez): **100 coin ≈ $1 baz değer** (tier1 paketi baz alınır). Bu oranla bölüm başına efektif fiyat $0.50–$1.00 aralığındadır; bonuslu paketlerde efektif coin maliyeti düşer.
- Coin **kapalı devre para birimidir**: yalnız uygulama içinde bölüm kilidi açmak için harcanır, iade edilmez, çekilmez, kullanıcılar arası transfer edilmez.

### 2.2 Coin paket kademeleri ve bonus oranları

Altı kademe, artan bonusla (kanonik fiyat noktaları; coin adetleri ShortSeries tasarımıdır ve remote config ile ayarlanabilir olmalıdır):

| Kademe | Product ID | Fiyat (USD) | Baz coin | Bonus | Bonus coin | Toplam coin | Efektif $/100 coin |
|---|---|---|---|---|---|---|---|
| Tier 1 | `com.shortseries.coins.tier1` | $0.99 | 100 | %0 | 0 | 100 | $0.99 |
| Tier 2 | `com.shortseries.coins.tier2` | $4.99 | 500 | %10 | 50 | 550 | $0.91 |
| Tier 3 | `com.shortseries.coins.tier3` | $9.99 | 1.000 | %20 | 200 | 1.200 | $0.83 |
| Tier 4 | `com.shortseries.coins.tier4` | $19.99 | 2.000 | %30 | 600 | 2.600 | $0.77 |
| Tier 5 | `com.shortseries.coins.tier5` | $49.99 | 5.000 | %60 | 3.000 | 8.000 | $0.62 |
| Tier 6 | `com.shortseries.coins.tier6` | $99.99 | 10.000 | %100 | 10.000 | 20.000 | $0.50 |

Tasarım gerekçeleri:

- Bonus merdiveni (%0→%100) kanona uygundur ve büyük paketleri belirgin biçimde avantajlı kılar; `CoinMagazasi`'nda bonus rozeti olarak gösterilir (§7).
- Tier 3 ($9.99) "en popüler" olarak işaretlenir (kategori alışkanlığı); Tier 5–6 "whale" segmentini hedefler.
- Coin adetleri **server'dan gelir**: ürün ID listesi `GET /config` yanıtındaki `coinProducts` alanından okunur; coin adetleri, bonus oranları ve rozet metinleri backend kataloğundan `productId` eşlemesiyle gelir (bkz. 05-veri-modeli-api.md). App Store product'ları yalnız fiyat/para birimi taşır; "kaç coin verileceği" backend kataloğunun kararıdır. Bu, bonus oranlarını App Store review'a takılmadan deneyle değiştirmeye imkân verir (§10). Değişiklik yalnız İLERİYE dönük işler; kullanıcının mevcut bakiyesi etkilenmez.

### 2.3 İlk yükleme 2x teklifi

- Hesap başına **bir kez**, kullanıcının ilk coin satın alımında geçerli: seçtiği paketin **toplam coin'i 2 katına çıkar** (baz + bonus dahil tüm miktar x2). Örnek: ilk alım Tier 3 ise 1.200 yerine 2.400 coin.
- Uygunluk server tarafından belirlenir (`firstTopUpEligible: true` — cüzdan durumu yanıtında). İstemci bunu asla lokal hesaplamaz; restore/yeniden kurulum/hesap bağlama senaryolarında tek doğruluk kaynağı backend'dir.
- UI: `CoinMagazasi` üstünde banner + her paket kartında "İlk yüklemeye özel 2x" rozeti (§7.3). `UnlockSheet` içindeki coin yetersiz akışında da vurgulanır.
- Kötüye kullanım notu: misafir hesap → satın al → hesabı sil → yeni misafir döngüsü fraud kontrolüne tabidir (§5.3); ilk yükleme uygunluğu cihaz sinyalleriyle çapraz kontrol edilebilir.

### 2.4 Purchased vs earned ayrımı ve harcama önceliği

**Purchased (satın alınmış) ve earned (kazanılmış) coin ayrımı zorunludur.** Gerekçe: muhasebe ve App Store komisyonu farkı — earned coin'ler IAP geliri değildir ve komisyon matrahına girmez; iade/chargeback senaryolarında yalnız purchased bakiye etkilenir.

Kurallar:

1. Cüzdan iki alt bakiye tutar: `purchasedBalance` ve `earnedBalance`. Kullanıcıya toplam gösterilir; ayrıntı `Profil` → cüzdan detayında ve `CoinMagazasi` başlığında görülebilir (toplam + "x'i kazanılmış" alt metni).
2. **Harcama önceliği: earned önce.** Bir unlock işleminde önce `earnedBalance` (son kullanma tarihi en yakın olandan başlayarak), yetmezse kalanı `purchasedBalance`'tan düşülür. Tek unlock iki alt bakiyeden karışık düşebilir; ledger'da iki ayrı satır oluşur (§5.2).
3. Harcama önceliği **server'da uygulanır**; istemci yalnız toplam bakiyeyi ve unlock sonucunu gösterir. İstemci tarafında öncelik hesabı yapılmaz (drift riski).
4. İade: bir coin paketi iade edildiğinde yalnız o pakete ait purchased coin'ler (ve ilk-yükleme 2x bonusu dahil paketle verilen tüm coin'ler) geri alınır; bakiye eksiye düşerse cüzdan eksi bakiyeyle işaretlenir ve yeni unlock'lar bakiye kapatılana dek engellenir (§5.1).

### 2.5 Earned coin son kullanma politikası

- Earned coin'ler **son kullanma tarihlidir**: her kazanım (check-in, görev, rewarded ad) kendi `expiresAt` değeriyle grant edilir. Varsayılan geçerlilik **30 gün** (remote config: `earnedCoinTTLDays`, aralık 14–90).
- Purchased coin'lerin son kullanma tarihi **yoktur**.
- Tüketim sırası earned içinde **en erken expire olandan başlar** (FEFO). Süresi dolan grant'ler server'da otomatik `expire` işlemiyle düşülür ve ledger'a yazılır.
- UX: `OdulMerkezi`'nde ve cüzdan detayında "7 gün içinde sona erecek X coin" uyarısı gösterilir; son kullanmaya 48 saat kala bir push/in-app hatırlatma tetiklenebilir (frekans limitleri 07-retention-gamification.md'ye tabidir). Bu, hem kayıp kaçınma (loss aversion) etkisiyle geri dönüş üretir hem de earned coin yükümlülüğünün bilançoda sınırsız birikmesini önler.
- Yasal not: son kullanma politikası kullanım koşullarında açıkça yazılmalı ve coin grant anında UI'da ("30 gün geçerli") belirtilmelidir.

### 2.6 Coin kazanım kaynakları (özet)

Ayrıntılı mekanikler 07-retention-gamification.md'dedir; ekonomiye etkisi açısından özet:

| Kaynak | Miktar | Sıklık sınırı |
|---|---|---|
| Günlük check-in | 10–50 coin, 7 günlük artan döngü + streak bonusu | Günde 1 |
| Görevler (izleme süresi, favorileme, paylaşma, bildirim izni) | Görev başına tanımlı; katalog server'dan | Görev başına tek seferlik / günlük |
| Rewarded ad (Faz 2) | Doğrudan bölüm kilidi açma veya küçük coin ödülü | Günde 5–10 (remote config, §9) |
| VIP günlük bonusu | VIP üyeye her gün otomatik earned coin grant'i (remote config: `vipDailyBonusCoins`) | Günde 1, VIP aktifken |

Ekonomi bekçi kuralı: ücretsiz kanallardan bir kullanıcının günde kazanabileceği toplam coin, ortalama bir bölüm kilidinin (75 coin) ~1–2 katını aşmamalıdır; aksi halde ödeme dönüşümü hedefi (%3) baskılanır. Toplam günlük earned tavanı remote config'tedir (`dailyEarnCapCoins`) ve deney konusudur (§10).

### 2.7 Ekonomi sağlık metrikleri

08-analitik-deney.md'deki event şemasıyla izlenecek göstergeler:

- ARPDAU, payer conversion (hedef ≥ %3), ilk satın almaya kadar geçen süre/bölüm sayısı
- Coin sink/source dengesi: harcanan / kazanılan+satın alınan oranı; earned coin expire oranı
- Paket dağılımı (tier mix), ilk-yükleme teklifinin alım oranı, tekrar satın alma (repeat purchase) oranı
- Unlock başına ortalama coin, seri tamamlama maliyeti dağılımı, VIP'e geçiş öncesi toplam coin harcaması
- Refund oranı (paket ve VIP ayrı ayrı)

---

## 3. IAP kataloğu

### 3.1 Product ID şeması

Şema: `com.shortseries.<ürünGrubu>.<kimlik>` — küçük harf, nokta ayraçlı, versiyonsuz. Product ID'ler App Store'da kalıcıdır ve silinse bile yeniden kullanılamaz; bu yüzden fiyat/coin adedi product ID'ye gömülmez (ör. `coins.500` DEĞİL, `coins.tier2`).

| Product ID | Tip | İçerik |
|---|---|---|
| `com.shortseries.coins.tier1` … `com.shortseries.coins.tier6` | Consumable | Coin paketleri (§2.2) |
| `com.shortseries.vip.weekly` | Auto-renewable subscription | Haftalık VIP |
| `com.shortseries.vip.monthly` | Auto-renewable subscription | Aylık VIP |
| `com.shortseries.vip.yearly` | Auto-renewable subscription | Yıllık VIP |

İleride eklenebilecekler (rezerve, Faz 1'de yok): `com.shortseries.offer.<kampanyaKimliği>` (sezonluk tek seferlik teklifler).

### 3.2 Fiyat tablosu

| Ürün | USD fiyat | Not |
|---|---|---|
| Coin Tier 1–6 | $0.99 / $4.99 / $9.99 / $19.99 / $49.99 / $99.99 | §2.2'deki coin adetleri backend kataloğundan |
| VIP haftalık | $5.99 | **Intro offer: ilk hafta $3.99** (pay-up-front, 1 hafta) |
| VIP aylık | $14.99 | — |
| VIP yıllık | $49.99 | Haftalık eşdeğeri ~$0.96 — "En avantajlı" rozeti |

VIP ayrıcalıkları (üç planda aynı): tüm bölümler açık + günlük bonus coin + reklamsız. Planlar yalnız süre/fiyatta ayrışır; bu yüzden **tek subscription group** içinde tanımlanır ve kullanıcı planlar arasında upgrade/downgrade yapabilir (App Store bunu otomatik oranlar).

### 3.3 App Store Connect yapılandırma notları

- **Subscription group:** `VIP` adında tek grup; weekly < monthly < yearly sıralaması (level) — upgrade anında geçer, downgrade dönem sonunda.
- **Introductory offer:** yalnız `com.shortseries.vip.weekly` üzerinde; tip *pay-up-front*, süre 1 hafta, fiyat $3.99. Uygunluğu StoreKit belirler (`isEligibleForIntroOffer`); istemci uygun olmayan kullanıcıya intro fiyatı GÖSTERMEZ (§8.2).
- **Family Sharing: KAPALI** — hem coin (consumable zaten paylaşılamaz) hem tüm VIP planları için ASC'de "Turn On Family Sharing" işaretlenmez. Gerekçe: entitlement tek hesaba bağlıdır; cüzdan ekonomisi hane paylaşımıyla uyumsuz. Bir kez açılırsa kapatılamayacağı için bu kararın kesinliği önemlidir.
- **Localization:** tüm product'lar için en az EN display name/description; TR/ES/PT ikinci dalga ile birlikte eklenir (bkz. 00-genel-bakis.md dil stratejisi).
- **Fiyatlandırma:** ABD baz fiyat + Apple'ın otomatik bölgesel fiyat noktaları; seçili pazarlarda manuel düzeltme (§12).
- **Tax category:** App Store Connect'te uygun vergi kategorisi seçilir (video streaming/dijital içerik); yanlış kategori bazı ülkelerde net geliri değiştirir — finans ekibiyle birlikte belirlenmelidir.
- **StoreKit configuration file:** repo'da `WalletKit/Tests/StoreKitConfig.storekit` — tüm product'ların lokal test tanımı; CI'da `StoreKitTest` framework ile satın alma akışı testleri koşulur.
- **Sandbox test matrisi:** intro offer uygunluğu, abonelik yenileme (sandbox hızlandırılmış süreler), iptal, iade, Ask to Buy (pending), interrupted purchase, billing retry/grace period.

---

## 4. StoreKit 2 implementasyonu

Tümü `WalletKit` modülünde yaşar (bkz. 03-mimari.md). Cüzdan durumu `WalletStore` actor'ünde tutulur; StoreKit erişimi `StoreKitService` üzerinden yapılır. Combine kullanılmaz; tamamı async/await.

### 4.1 Genel akış

```
CoinMagazasi/VIPAbonelik ──► StoreKitService.purchase(product)
        │                            │
        │                            ▼
        │               StoreKit 2 purchase() → verified Transaction (JWS)
        │                            │
        │                            ▼
        │               WalletAPI.submitTransaction(jws)  ── backend doğrular
        │                            │                       (App Store Server API)
        │                            ▼
        │               Backend cüzdanı kredi eder / entitlement açar
        │                            │
        │                            ▼
        │               transaction.finish()  ◄── YALNIZ backend onayından SONRA
        ▼
WalletStore.refresh() → UI bakiye/entitlement günceller
```

**Kritik kural:** consumable coin işlemlerinde `finish()` yalnız backend cüzdanı kredi ettikten sonra çağrılır. Erken `finish()` + backend hatası = kullanıcı parasını verdiği coin'i alamaz ve transaction bir daha `Transaction.updates`'te görünmez. Bitirilmemiş transaction'lar her app açılışında `Transaction.updates` / `Transaction.unfinished` üzerinden yeniden teslim edilir; backend idempotent olduğu için (§5.2) tekrar gönderim güvenlidir.

### 4.2 Product ID tanımları ve Product yükleme

```swift
// WalletKit/Sources/Store/ProductCatalog.swift
enum ShortSeriesProduct {
    static let coinTiers: [String] = (1...6).map { "com.shortseries.coins.tier\($0)" }
    static let vipWeekly  = "com.shortseries.vip.weekly"
    static let vipMonthly = "com.shortseries.vip.monthly"
    static let vipYearly  = "com.shortseries.vip.yearly"
    static var all: [String] { coinTiers + [vipWeekly, vipMonthly, vipYearly] }
}

// WalletKit/Sources/Store/StoreKitService.swift
import StoreKit

final class StoreKitService: Sendable {
    /// App Store'dan product'ları yükler. Sonuç WalletStore'da cache'lenir;
    /// başarısızsa CoinMagazasi "yükleniyor/yeniden dene" durumunu gösterir (§7.5).
    func loadProducts() async throws -> LoadedProducts {
        let products = try await Product.products(for: ShortSeriesProduct.all)
        let coins = products
            .filter { $0.type == .consumable }
            .sorted { $0.price < $1.price }
        let subs = products.filter { $0.type == .autoRenewable }
        // Backend paket kataloğu (coin adetleri, bonus oranları, ilk-yükleme uygunluğu)
        // ayrı çağrıyla gelir ve productID üzerinden eşlenir (05-veri-modeli-api.md).
        return LoadedProducts(coinPacks: coins, vipPlans: subs)
    }
}
```

Notlar:

- `Product.products(for:)` sonucu eksik ID döndürebilir (ASC'de reddedilmiş/pasif product). Eksik ID durumunda ilgili kart UI'da gizlenir ve `iap_product_missing` event'i loglanır.
- Fiyat gösteriminde **her zaman** `product.displayPrice` kullanılır (yerelleştirilmiş, storefront para biriminde). USD tutarlar asla hardcode edilmez (§11.2).

### 4.3 purchase()

```swift
enum PurchaseOutcome { case success, cancelled, pending }

extension StoreKitService {
    /// - Parameter appAccountToken: backend kullanıcı kimliğinden türetilmiş UUID.
    ///   Transaction'ı ShortSeries hesabına bağlar; server doğrulamada eşleşme kontrol edilir.
    func purchase(_ product: Product, appAccountToken: UUID) async throws -> PurchaseOutcome {
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)   // §4.5 — lokal JWS kontrolü
            try await submitToBackend(jws: verification.jwsRepresentation,
                                      transactionID: transaction.id)
            await transaction.finish()                          // YALNIZ backend onayından sonra
            return .success

        case .userCancelled:
            return .cancelled                                   // sessiz; hata gösterilmez (§7.5)

        case .pending:
            return .pending                                     // Ask to Buy / SCA — §4.9

        @unknown default:
            throw WalletError.unknownPurchaseResult
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw WalletError.failedVerification(error)
        }
    }
}
```

- `appAccountToken`: misafir hesap dahil her kullanıcının backend `userId`'sinden deterministik UUID (UUIDv5) üretilir. Misafir → Apple/Google/e-posta bağlama sonrasında aynı cüzdan korunur (bkz. 05-veri-modeli-api.md hesap birleştirme).
- `submitToBackend` başarısız olursa (ağ/5xx): `finish()` ÇAĞRILMAZ, kullanıcıya "Satın alma alındı, coin'ler birazdan yüklenecek" bilgisi gösterilir; retry `Transaction.updates` üzerinden otomatik yürür (§4.4).

### 4.4 Transaction.updates dinleyicisi

```swift
// ShortSeriesApp bileşiminde, app launch'ta BİR KEZ başlatılır (03-mimari.md DI kompozisyonu).
final class TransactionObserver {
    private var task: Task<Void, Never>?

    func start(walletStore: WalletStore, service: StoreKitService) {
        task = Task.detached(priority: .background) {
            // 1) Önceki oturumlardan kalan bitirilmemiş transaction'lar
            for await result in Transaction.unfinished {
                await service.handle(result, walletStore: walletStore)
            }
            // 2) Canlı güncellemeler: yenileme, iade, Ask to Buy onayı,
            //    App Store'dan (Manage Subscriptions, offer code) yapılan işlemler
            for await result in Transaction.updates {
                await service.handle(result, walletStore: walletStore)
            }
        }
    }
}

extension StoreKitService {
    func handle(_ result: VerificationResult<Transaction>, walletStore: WalletStore) async {
        guard let transaction = try? checkVerified(result) else { return }
        do {
            if transaction.revocationDate != nil {
                // İade/revoke — backend zaten Notifications V2 ile bilir; lokal state tazele
                await walletStore.refresh()
            } else {
                try await submitToBackend(jws: result.jwsRepresentation,
                                          transactionID: transaction.id)
                await walletStore.refresh()
            }
            await transaction.finish()
        } catch {
            // finish etme — sonraki updates turunda tekrar gelir
            Log.wallet.error("transaction submit failed: \(error)")
        }
    }
}
```

Dinleyici, uygulama açıkken App Store kaynaklı her değişikliği yakalar: abonelik yenilemesi, iade, fiyat artışı onayı, Ask to Buy sonucu. Kaçırılan olaylar için asıl güvence server tarafındaki Notifications V2'dir (§5.1); istemci foreground'a dönüşte `WalletStore.refresh()` çağırır.

### 4.5 Doğrulama akışı: JWS → backend → App Store Server API

İki katmanlı doğrulama:

1. **İstemci (StoreKit 2 otomatik):** `VerificationResult` — StoreKit, transaction JWS imzasını cihazda doğrular. `unverified` sonuç reddedilir. Bu katman UI hızı içindir, güven kaynağı DEĞİLDİR.
2. **Server (asıl güven):** istemci `jwsRepresentation`'ı backend'e gönderir (`POST /iap/verify`). Backend:
   - JWS imza zincirini Apple root sertifikasına kadar doğrular,
   - `transactionId` daha önce işlendiyse aynı sonucu döner (idempotency, §5.2),
   - gerekirse App Store Server API'den (`GET /inApps/v1/transactions/{transactionId}`) işlemin güncel durumunu teyit eder,
   - `appAccountToken` ↔ istekteki kullanıcı eşleşmesini kontrol eder (transaction başka hesaba enjekte edilemez),
   - `environment` alanını kontrol eder (production build'e sandbox transaction kabul edilmez),
   - coin ise cüzdanı kredi eder, VIP ise entitlement yazar; yanıtta güncel cüzdan/entitlement snapshot'ı döner.

**Entitlement doğruluk kaynağı backend'dir.** İstemci `Transaction.currentEntitlements`'ı yalnız çevrimdışı/ilk açılış iyimser durumu için kullanır; sunucuya ulaşıldığı anda backend snapshot'ı kazanır. Çakışmada (lokal VIP diyor, backend hayır) backend geçerlidir ve `entitlement_mismatch` event'i loglanır.

### 4.6 Restore

```swift
// VIPAbonelik ve Ayarlar'daki "Satın Alımları Geri Yükle" butonu
func restorePurchases() async throws {
    try await AppStore.sync()          // App Store ile senkronizasyon (kullanıcı auth görebilir)
    await walletStore.refresh()        // backend snapshot'ı yeniden çek
}
```

- StoreKit 2'de aktif entitlement'lar zaten `Transaction.currentEntitlements` ile otomatik gelir; `AppStore.sync()` yalnız kullanıcının açıkça "geri yükle" dediği durumda çağrılır (Apple önerisi). Buton yine de **zorunludur** (§11.3).
- **Coin'ler consumable'dır ve restore edilmez** — bakiye backend cüzdanında yaşar; cihaz değişiminde hesapla (misafir hesap bağlanmışsa) otomatik gelir. `VIPAbonelik` ve `CoinMagazasi`'ndaki restore açıklaması bunu netleştirir: "Geri yükleme aboneliğinizi tanır; coin bakiyeniz hesabınızda saklıdır."
- Misafir hesap + cihaz değişimi = cüzdana erişim kaybı riski. İlk satın alma başarısından sonra kullanıcıya hesap bağlama teklifi gösterilir ("Bakiyeni kaybetme — hesabını bağla", bkz. 02-ekran-haritasi-navigasyon.md akışı).

### 4.7 Aile paylaşımı

**KAPALI.** ASC'de hiçbir product için Family Sharing etkinleştirilmez (§3.3). Kodda `transaction.ownershipType == .familyShared` görülürse (teorik olarak gelmemeli) işlem reddedilir ve loglanır — savunmacı kontrol.

### 4.8 Intro offer (VIP haftalık, ilk hafta $3.99)

```swift
struct VIPPlanViewState {
    let product: Product
    let introEligible: Bool
    /// UI metni: intro varsa "İlk hafta \(introPrice), sonra \(regularPrice)/hafta"
}

func vipPlanState(for product: Product) async -> VIPPlanViewState {
    guard let sub = product.subscription else { return .init(product: product, introEligible: false) }
    let eligible = await sub.isEligibleForIntroOffer   // StoreKit uygunluğu belirler
    return .init(product: product, introEligible: eligible && sub.introductoryOffer != nil)
}
```

- Intro fiyat ve süre UI'da **StoreKit'ten okunur**: `sub.introductoryOffer?.displayPrice`, `periodCount`, `paymentMode`. $3.99 metni hardcode edilmez.
- Uygun olmayan kullanıcı (daha önce intro kullanmış / aynı subscription group'ta abone olmuş) yalnız normal fiyatı görür. Intro'lu ve intro'suz UI durumlarının ikisi de tasarlanır (§8.2).
- Server tarafında Notifications V2 `offerType` alanı intro dönem gelirini normal dönemden ayırt eder (raporlama).

### 4.9 Edge case'ler ve kabul kriterleri

Edge case'ler:

| Durum | Beklenen davranış |
|---|---|
| Ask to Buy (`pending`) | UI "Onay bekleniyor" bilgisi; onay gelince `Transaction.updates` yakalar, coin/VIP işlenir |
| Satın alma sırasında app kill | Açılışta `Transaction.unfinished` işler; kullanıcı coin'i kaybetmez |
| Backend down, satın alma başarılı | `finish()` ertelenir; "coin'ler birazdan yüklenecek" durumu; otomatik retry |
| Aynı JWS iki kez gönderildi | Backend idempotent — tek kredi, aynı yanıt (§5.2) |
| Sandbox transaction production'da | Backend reddeder, fraud loguna düşer |
| Abonelik süresince fiyat artışı | Apple onay akışı yürütür; `updates` + Notifications V2 durumu bildirir |
| Billing retry / grace period | Entitlement grace boyunca korunur; `VIPAbonelik`'te "ödeme sorunu" banner'ı (§8.4) |
| Storefront değişimi (ülke) | Product'lar yeniden yüklenir; `displayPrice` yeni para biriminde |
| VIP aktifken coin satın alma | Serbest — coin'ler VIP bitince de geçerli |

Kabul kriterleri (Faz 1 çıkışı için):

- [ ] Tüm satın alma yolları (başarı/iptal/pending/hata/kill-restart) StoreKitTest ile otomasyon testinde.
- [ ] Consumable hiçbir yolda backend onayından önce `finish()` edilmiyor (kod incelemesi + test).
- [ ] Uçak modunda satın alma denemesi anlamlı hata gösteriyor; uygulama kilitlenmiyor.
- [ ] Restore butonu VIP'i 5 sn içinde tanıyor; coin bakiyesi hesap üzerinden geliyor.
- [ ] Intro offer yalnız uygun kullanıcıya görünüyor (sandbox: yeni hesap vs intro tüketmiş hesap).
- [ ] Entitlement backend/istemci uyuşmazlığında backend kazanıyor ve event loglanıyor.

---

## 5. Server tarafı beklentiler

Bu bölüm iOS ekibinin backend'den beklediği sözleşmeyi tanımlar; şema ayrıntıları 05-veri-modeli-api.md'dedir.

### 5.1 App Store Server Notifications V2

Backend, ASC'de tanımlı V2 endpoint'i üzerinden signedPayload (JWS) bildirimlerini alır, imzayı doğrular ve işler:

| notificationType (subtype) | Aksiyon |
|---|---|
| `SUBSCRIBED` (INITIAL_BUY / RESUBSCRIBE) | VIP entitlement aç, bitiş tarihini yaz |
| `DID_RENEW` | Entitlement süresini uzat; günlük bonus coin akışı devam |
| `DID_CHANGE_RENEWAL_STATUS` (AUTO_RENEW_DISABLED) | Entitlement DEĞİŞMEZ (dönem sonuna dek sürer); churn-risk işaretle, win-back segmentine al |
| `DID_FAIL_TO_RENEW` (GRACE_PERIOD) | Entitlement grace boyunca korunur; istemciye "ödeme sorunu" durumu servis edilir |
| `EXPIRED` | Entitlement kapat; istemci bir sonraki refresh'te düşürülmüş durumu görür |
| `REFUND` | VIP ise entitlement derhal kapat; coin paketi ise ilgili grant'i geri al — bakiye eksiye düşebilir (§2.4), eksi bakiye yeni unlock'ları bloklar |
| `REFUND_DECLINED` | Kayıt amaçlı log |
| `DID_CHANGE_RENEWAL_PREF` (UPGRADE/DOWNGRADE) | Plan değişikliğini entitlement'a yansıt (upgrade anında, downgrade dönem sonunda) |
| `REVOKE` | Entitlement derhal kapat |

Genel kurallar: bildirimler sırasız/mükerrer gelebilir → her bildirim `notificationUUID` ile idempotent işlenir ve `signedDate` + transaction sürümü karşılaştırmasıyla eski bildirim yenisini ezmez. Kaçan bildirimlere karşı günlük reconciliation job'ı App Store Server API'den abonelik durumlarını tarar.

### 5.2 Cüzdan: idempotency ve double-entry

- **Idempotency:** her cüzdan mutasyonu benzersiz anahtar taşır ve güvenle tekrar edilebilir:
  - IAP kredisi → `transactionId`
  - Bölüm unlock → `(userId, episodeId)` doğal anahtarı — bir bölüm bir kullanıcı için yalnız bir kez ücretlendirilir; tekrar istek aynı başarılı yanıtı döner, ikinci kez düşüm yapılmaz
  - Ödül grant'leri → `(userId, rewardType, dönemAnahtarı)` (ör. check-in için gün)
  - Rewarded ad ödülü → reklam sağlayıcının S2S callback nonce'u (§9.4)
- **Double-entry:** her hareket iki bacaklı ledger kaydıdır (kaynak hesap / hedef hesap); bakiye ledger toplamından türetilir, ayrı yazılan bakiye alanı yalnızca cache'tir. Purchased ve earned ayrı alt hesaplardır; tek unlock earned+purchased karışık düştüğünde iki satır oluşur (§2.4). Tam audit trail: kim, ne zaman, hangi işlem, hangi bakiyeden.
- **Tutarlılık:** istemci `WalletStore.refresh()` çağrılarında tek snapshot endpoint'inden (`GET /wallet`) toplam/alt bakiyeler + entitlement + `firstTopUpEligible` alır. Bakiye istemcide asla lokal aritmetikle güncellenmez; her mutasyon yanıtı yeni snapshot döner.

### 5.3 Fraud kontrolleri

Backend asgari kontrol seti (kanon §5):

- **Receipt replay:** `transactionId` tekilliği; farklı hesaba aynı JWS enjeksiyonu `appAccountToken` eşleşmesiyle engellenir (§4.5).
- **Jailbreak/tamper sinyalleri:** istemci temel sinyalleri toplar (best-effort); server risk skoruna girdi olur. Jailbreak tek başına blok sebebi değildir, anomaliyle birleşince manuel inceleme kuyruğuna düşer.
- **Anormal kazanç hızı:** earned coin kaynaklarında hız limitleri (check-in günde 1, rewarded ad cap'i, görev tekilliği); limit üstü denemeler reddedilir ve skorlanır.
- **İlk-yükleme teklifi istismarı:** hesap silme/yeniden yaratma döngüsüne karşı cihaz-düzeyi sinyal korelasyonu (§2.3).
- **İade istismarı:** REFUND sonrası eksi bakiye + tekrarlayan iade pattern'inde cüzdan kısıtlaması.
- **Sandbox/production ayrımı:** environment kontrolü (§4.5).

---

## 6. UnlockSheet UX spesifikasyonu

`UnlockSheet`, kilitli bölümle karşılaşan kullanıcıya sunulan paywall sheet'idir. `WalletKit` içinde yaşar; `PlayerFeed`, `BolumListesi` ve `DiziDetay`'dan tetiklenir (navigasyon 02-ekran-haritasi-navigasyon.md).

### 6.1 Tetiklenme noktaları

1. **PlayerFeed akışı (birincil):** kullanıcı swipe ile kilitli bölüme geldiğinde player oynatmaz; bölümün blur'lu kapak karesi + kilit ikonu üzerine `UnlockSheet` otomatik açılır (player davranışı 04-player-engine.md). Bu an tasarım gereği cliffhanger sonrasına denk gelir — kategori pratiğinde paywall'ın en yüksek dönüşüm ürettiği nokta.
2. **BolumListesi:** kilitli bölüme (kilit ikonu + coin fiyatı görünür) dokununca.
3. **DiziDetay:** "İzlemeye Başla / Devam Et" CTA'sı kilitli bölüme denk geliyorsa.
4. **Push/deep link:** hedef bölüm kilitliyse, hedef ekran açıldıktan sonra sheet gösterilir.

VIP entitlement aktifse `UnlockSheet` hiçbir yolda gösterilmez; bölüm doğrudan oynar.

### 6.2 İçerik ve seçenek sıralaması

Sheet düzeni (yukarıdan aşağı):

1. **Başlık bloğu:** dizi adı + bölüm numarası, "Bu bölüm kilitli" mesajı, kullanıcının güncel coin bakiyesi.
2. **Birincil buton — coin ile aç:** "`{unlockPrice}` coin ile kilidi aç". Görünür satırlar içinde HER ZAMAN ilk sırada (görünürlük sözleşmesi aşağıda). Bakiye yeterliyse aktif ve vurgulu.
3. **Otomatik-unlock toggle'ı (binge modu):** birincil butonun hemen altında — §6.4.
4. **İkincil — reklam izle (Faz 2):** "Reklam izle, bölümü aç" + kalan günlük hak göstergesi ("Bugün 3/5 hak kaldı"). Faz 1'de bu satır hiç render edilmez. Reklam yüklü değilse/cap dolduysa davranış §9.5.
5. **Üçüncül — VIP upsell:** "VIP ol — tüm bölümler açık + günlük bonus coin + reklamsız" satırı; dokununca `VIPAbonelik` açılır. Intro offer uygunsa satırda intro fiyat vurgusu (`displayPrice` ile).
6. Kapatma: aşağı çekme veya X — kullanıcı sheet'i her zaman ödemeye zorlanmadan kapatabilir; `PlayerFeed`'de bir sonraki diziye swipe serbest kalır.

**Seçenek görünürlüğü sözleşmesi:** `UnlockSheet`'in üç satırı (coin / reklam / VIP) **tek tek server bayrağıyla kapatılabilir**; görünür satır seti `GET /config` yanıtından türer (bkz. 05-veri-modeli-api.md), istemcide satır listesi hardcode edilmez:

| Bayrak | Kapattığı satır | Not |
|---|---|---|
| `monetization.coin_enabled` | Coin ile aç satırı + otomatik-unlock toggle'ı (§6.4) | `ads.rewarded_enabled` kalıbı örnek alınarak tanımlanır; kapalıyken coin-yetersiz akışı (§6.3) da devre dışıdır |
| `ads.rewarded_enabled` | Reklam izle satırı (Faz 2) | Günlük cap'ten (§9.2) bağımsız ana şalterdir; Faz 1'de zaten kapalıdır |
| `monetization.vip_enabled` | VIP upsell satırı | |

Amaç: iş modeli pivotu (ör. salt-VIP modeline geçiş, reklamın tamamen kapatılması) **istemci sürümü beklemeden server'dan degrade edilebilir** olsun. Bayrağı kapalı satır hiç render edilmez; en az bir satırın görünür kalması server config doğrulamasıyla garanti edilir (üçü birden kapatılamaz). Sabit sıralama kuralı (coin → reklam → VIP) **yalnız görünür satırlar için** geçerlidir; sıralama varyasyonunu yalnız A/B deneyi değiştirir (§10).

### 6.3 Coin yetersiz akışı

- Bakiye < `unlockPrice` ise birincil buton "`{unlockPrice}` coin gerekli — Coin Mağazası'na git" halini alır; eksik miktar gösterilir ("32 coin daha gerekli").
- Dokununca `CoinMagazasi` aynı sheet yığını içinde push edilir (tam ekran geçiş yok; bağlam korunur). İlk yükleme teklifi uygunsa banner öne çıkar.
- Başarılı satın alma sonrası otomatik olarak `UnlockSheet`'e geri dönülür; bakiye güncellenmiş, birincil buton aktif. **Unlock otomatik yürütülmez** — kullanıcı son dokunuşu kendisi yapar (sürpriz harcama şikâyeti/iade riskini düşürür). İstisna: otomatik-unlock toggle'ı açıksa (§6.4) dönüşte bekleyen bölüm sormadan açılır.
- Satın alma iptal edilirse `UnlockSheet`'e eski haliyle dönülür.

### 6.4 Otomatik-unlock toggle'ı (binge modu)

- Etiket: **"Sonraki bölümleri otomatik aç"** + alt metin "Kilitli bölümler sorulmadan coin ile açılır".
- Kapsam: **dizi başına** ayardır, server'da saklanır (`autoUnlock: true` — dizi bazlı kullanıcı tercihi, 05-veri-modeli-api.md). Varsayılan: kapalı (remote config `autoUnlockDefault` deneye açık, §10).
- Açıkken davranış: `PlayerFeed`'de kilitli bölüme gelindiğinde sheet gösterilmez; unlock isteği arka planda atılır, kısa bir toast görünür ("Bölüm 12 açıldı · −75 coin · bakiye 340") ve oynatma kesintisiz devam eder. Toast'ta "Geri al" YOKTUR (unlock kalıcıdır) ama toggle'ı kapatan hızlı eylem vardır.
- Bakiye yetersiz kalırsa binge zinciri durur ve `UnlockSheet` normal akışla (coin yetersiz durumu, §6.3) gösterilir.
- Rewarded ad ve VIP, otomatik-unlock kapsamında değildir; otomatik akış yalnız coin harcar.
- Kabul kriteri: otomatik-unlock hiçbir durumda aynı bölümü iki kez ücretlendiremez (server idempotency §5.2) ve saniyeler içinde art arda swipe edilen çoklu kilitli bölümlerde istekler sıralı, teker teker işlenir (aynı anda en fazla 1 bekleyen unlock).

### 6.5 Görsel/etkileşim gereksinimleri

- Sheet, `PlayerFeed` üstünde medium detent ile açılır; arka planda blur'lu kapak karesi görünür kalır (bağlam hissi). Dark theme first (DesignSystem).
- Coin fiyatı ve bakiye `WalletStore` snapshot'ından; sheet açıkken bakiye değişirse (ör. arka planda ödül grant'i) UI canlı güncellenir (`@Observable`).
- Unlock isteği sürerken birincil buton spinner'lı ve kilitli; çift dokunma engellenir.

### 6.6 Edge case'ler

| Durum | Davranış |
|---|---|
| Unlock isteğinde ağ hatası | Buton eski haline döner, inline hata: "Bağlantı sorunu, tekrar dene" — coin düşülmediği backend snapshot ile teyit edilir |
| Fiyat sheet açıkken değişti (deney/katalog) | Server 409 + güncel fiyat döner; UI fiyatı günceller ve bir kez "Fiyat güncellendi" uyarısı gösterir; otomatik harcama yapılmaz |
| `unlockPrice` alınamadı | Birincil buton devre dışı + "Fiyat yüklenemedi, tekrar dene"; reklam/VIP seçenekleri çalışır kalır |
| Unlock başarılı ama yanıt kayboldu | İstemci retry eder; idempotent server aynı başarıyı döner, çift ücret yok |
| Eksi bakiye (iade sonrası) | Tüm unlock'lar bloklu; sheet "Bakiye sorunu" durumu + `CoinMagazasi` yönlendirmesi gösterir |
| VIP satın alma sheet'ten tamamlandı | Sheet kapanır, bölüm otomatik oynar |
| Aynı anda başka cihazda unlock | Refresh'te bölüm açık görünür; sheet açıksa kapanır ve oynatma başlar |

### 6.7 Analitik

Sheet gösterimi (`paywall_shown`: kaynak, dizi, bölüm, fiyat, bakiye), seçenek dokunuşları, unlock sonucu, coin-yetersiz → mağaza dönüşümü, otomatik-unlock açma/kapama — tam şema 08-analitik-deney.md.

---

## 7. CoinMagazasi UX

`CoinMagazasi` coin paketlerinin satıldığı ekrandır. Girişler: `UnlockSheet` coin-yetersiz akışı (sheet içi push), `Profil` cüzdan alanı, `OdulMerkezi` bakiye kartı.

### 7.1 Düzen

1. **Başlık:** güncel toplam bakiye (+ "x'i kazanılmış" alt metni, §2.4); earned coin'lerde yaklaşan son kullanma uyarısı (§2.5).
2. **İlk yükleme banner'ı** (uygunsa): "İlk yüklemene özel: aldığın coin 2 KAT!" — §7.3.
3. **Paket kartları:** 6 kart, dikey liste (küçükten büyüğe). Kart içeriği: toplam coin (büyük punto), baz + bonus dökümü ("1.000 + 200 bonus"), `displayPrice`, bonus rozeti.
4. **Alt bilgi:** "Coin'ler yalnız uygulama içinde geçerlidir, iade edilmez" + Kullanım Koşulları / Gizlilik linkleri + "Satın Alımları Geri Yükle" butonu (VIP için; coin'lerin hesapta saklandığı açıklamasıyla, §4.6).

### 7.2 Bonus rozetleri

- Tier 2–6 kartlarında sağ üst köşe rozeti: "+%10 BONUS" … "+%100 BONUS". Tier 1 rozetsiz.
- Tier 3 karta "EN POPÜLER" ikinci rozeti; Tier 6'ya "EN İYİ DEĞER". Rozet metinleri backend kataloğundan gelir (deneyle değiştirilebilir).

### 7.3 İlk yükleme banner'ı

- Yalnız `firstTopUpEligible: true` iken görünür (server kararı, §2.3). Banner + tüm kartlarda 2x sonrası toplam coin gösterimi: "2.400 coin" büyük, altında üstü çizili "1.200".
- İlk satın alma tamamlandığı anda banner ve 2x gösterimleri kaybolur (snapshot yenilenir).
- Banner'da geri sayım/suni aciliyet YOK (Faz 1) — dark pattern riski ve review hassasiyeti; aciliyet varyantı ancak deney olarak ve yasal onayla düşünülür (§10).

### 7.4 Satın alma durumları

| Durum | UI |
|---|---|
| Product'lar yükleniyor | Skeleton kartlar; 10 sn'de yüklenmezse "Yeniden dene" |
| Product listesi alınamadı | Boş durum + retry; `iap_products_load_failed` loglanır |
| Satın alma sürüyor | Seçilen kart spinner'lı, diğer kartlar devre dışı; sheet kapatma engellenmez ama işlem arka planda sürer |
| Başarılı | Bakiye sayaç animasyonuyla artar + başarı toast'ı; `UnlockSheet`'ten gelindiyse otomatik geri dönüş (§6.3) |
| İptal (`userCancelled`) | Sessiz — hata gösterilmez, kartlar normale döner |
| Pending (Ask to Buy) | Bilgi kutusu: "Onay bekleniyor. Onaylanınca coin'ler eklenecek." |
| Hata (StoreKit/ağ) | Alert: kısa hata + "Tekrar dene"; teknik kod loglanır |
| Satın alındı ama backend kredisi gecikti | "Ödemen alındı, coin'ler birazdan hesabında" kalıcı olmayan banner; otomatik retry (§4.4) |

### 7.5 Kabul kriterleri

- [ ] Tüm fiyatlar `displayPrice` ile, storefront para biriminde gösteriliyor.
- [ ] İlk yükleme durumu yalnız server verisiyle belirleniyor; UI lokal tahmin yapmıyor.
- [ ] İptal edilen satın alma hiçbir hata UI'ı üretmiyor.
- [ ] Çift dokunuşla çift satın alma tetiklenemiyor.
- [ ] VoiceOver: kart etiketi "1.200 coin, %20 bonus dahil, 9 dolar 99 sent" formatında okunuyor.

---

## 8. VIPAbonelik UX

`VIPAbonelik` abonelik planlarının satıldığı ve yönetildiği ekrandır. Girişler: `UnlockSheet` upsell satırı, `Profil` VIP durumu alanı, `CoinMagazasi` çapraz linki, kampanya push'ları.

### 8.1 Plan karşılaştırma

- Üst blok: VIP ayrıcalıkları (ikonlu 3 satır): **tüm bölümler açık**, **günlük bonus coin**, **reklamsız**.
- Plan kartları (yatay 3 seçenek): Haftalık $5.99 / Aylık $14.99 / Yıllık $49.99. Her kartta: dönem, `displayPrice`, haftalık eşdeğer maliyet ("≈$0.96/hafta"), yıllıkta "EN AVANTAJLI" rozeti. Varsayılan seçim: yıllık (deney konusu, §10).
- Haftalık kartta intro offer uygunsa: "İlk hafta $3.99, sonra $5.99/hafta" — metin tamamen StoreKit verisinden (§4.8).
- CTA: "VIP Ol" tek buton (seçili plana göre); altında otomatik yenileme açıklaması (§11.4) ve Kullanım Koşulları/Gizlilik linkleri; **"Satın Alımları Geri Yükle"** butonu her zaman görünür.

### 8.2 Abone olmayan / intro'suz durumlar

- Intro uygun değilse haftalık kart yalnız normal fiyat gösterir; "ilk hafta" metni hiç render edilmez.
- Zaten VIP olan kullanıcı bu ekranda satın alma yerine **yönetim görünümünü** görür (§8.3).

### 8.3 Yönetim

- Aktif VIP görünümü: mevcut plan, yenileme tarihi ("12 Ağustos'ta yenilenecek"), günlük bonus coin durumu.
- **"Aboneliği Yönet"** butonu → `showManageSubscriptions(in:)` (StoreKit sheet) çağrılır; başarısız olursa fallback olarak iOS abonelik ayarları deep link'i (`https://apps.apple.com/account/subscriptions`) açılır. Plan değiştirme (upgrade/downgrade) ve iptal bu akışta Apple UI'ıyla yapılır — uygulama içinde ayrı iptal akışı yazılmaz.
- Auto-renew kapatılmışsa (Notifications V2 → churn-risk, §5.1): "Aboneliğin {tarih}te sona erecek" bilgisi + win-back mesajı gösterilebilir (frekans kuralları 07-retention-gamification.md).

### 8.4 İptal / iade / ödeme sorunu sonrası entitlement düşürme

| Olay | Entitlement | UX |
|---|---|---|
| Kullanıcı auto-renew'u kapattı | Dönem sonuna kadar sürer | Bitiş tarihi bilgisi; erişim kaybı YAŞANMAZ |
| Dönem doldu (`EXPIRED`) | Kapanır | Bir sonraki `WalletStore.refresh`'te kilitler geri gelir; kilitli bölüme gelen eski VIP'e `UnlockSheet` normal akışla gösterilir + "VIP'in sona erdi, yenile" satırı |
| İade (`REFUND`/`REVOKE`) | **Derhal** kapanır | İstemci foreground refresh'inde durumu görür; oynatılmakta olan bölüm kesilmez, bir SONRAKİ kilitli bölümde paywall devreye girer |
| Billing retry / grace period | Grace boyunca korunur | `VIPAbonelik` ve `Profil`'de "Ödeme yöntemini güncelle" banner'ı; dokununca Apple ödeme ayarlarına yönlendirme |

Düşürme anında izleme geçmişi, coin bakiyesi ve coin ile daha önce açılan bölümler etkilenmez (unlock kalıcıdır).

### 8.5 Kabul kriterleri

- [ ] Üç planın da satın alımı sandbox'ta uçtan uca doğrulandı (intro dahil).
- [ ] Upgrade/downgrade sonrası entitlement doğru plana geçiyor (upgrade anında, downgrade dönem sonunda).
- [ ] İade sonrası entitlement tek refresh'te düşüyor; uygulama yeniden kurulumda VIP hayaleti kalmıyor.
- [ ] Yönetim butonu StoreKit sheet açılamadığında ayarlar deep link'ine düşüyor.
- [ ] Otomatik yenileme açıklaması ve fiyat/dönem bilgisi satın alma butonunun görünür yakınında (§11.4).

---

## 9. Rewarded ads (Faz 2)

Reklamla kilit açma Faz 2 kapsamındadır (bkz. 01-ozellik-envanteri.md, 09-yol-haritasi-tasklar.md). Birincil aday: **AdMob** (rewarded ad formatı). Entegrasyon `RewardsKit` içinde yaşar; `UnlockSheet` ve `OdulMerkezi` yüzeylerinde görünür.

### 9.1 Yüzeyler

- `UnlockSheet` ikinci seçenek: "Reklam izle, bölümü aç" (§6.2) — reklam tamamlanınca **ilgili bölümün kilidi doğrudan açılır** (coin düşmez, coin grant edilmez; unlock ledger'a `source: rewardedAd` ile yazılır).
- `OdulMerkezi` rewarded ad kartı: reklam izle → küçük coin ödülü (earned, son kullanma tarihli). Bölüm-unlock ile aynı günlük cap havuzunu paylaşır.

### 9.2 Günlük cap

- **Günde 5–10 gösterim, remote config ile** (`rewardedAdDailyCap`, varsayılan 5; kategori pratiği ~5/gün). Cap kullanıcı-gün bazında server'da sayılır (cihaz değiştirme/saat oynatmayla aşılamaz); gün sınırı kullanıcının saat dilimine göre 00:00.
- UI her yüzeyde kalan hakkı gösterir ("Bugün 3/5"). Cap dolunca seçenek devre dışı + "Yarın yeni hakların olacak" metni; `UnlockSheet`'te coin/VIP seçenekleri öne çıkar (cap, tasarım gereği ödemeye dönüşüm baskısıdır).

### 9.3 Yükleme / gösterim / ödül akışı

Rewarded ad entegrasyonu **sağlayıcı-agnostiktir**: `RewardsKit` içindeki yüzeyler (`UnlockSheet`, `OdulMerkezi`) reklam SDK'sını doğrudan görmez; yalnız `RewardsKit`'in tanımladığı `RewardedAdProviding` protokolünü kullanır. Somut sağlayıcı kodu `RewardsKit/AdBridge` altında yaşar ve DI kompozisyonunda (`ShortSeriesApp`, bkz. 03-mimari.md) bağlanır. **Sağlayıcı değişimi = yeni bridge + DI kompozisyonu; başka modül dokunmaz.**

```swift
// RewardsKit/Sources/Ads/RewardedAdProviding.swift — normatif, sağlayıcı-bağımsız sözleşme
/// Rewarded ad portu. RewardsKit yüzeyleri yalnız bu protokolü görür;
/// reklam SDK'sı tipleri bu imzalarda GÖRÜNEMEZ.
protocol RewardedAdProviding: AnyObject {
    /// Ön-yükleme: UnlockSheet gösterilmeden ÖNCE tetiklenir (kilitli bölüme yaklaşırken,
    /// 04-player-engine.md prefetch sinyaliyle) — sheet açıldığında reklam hazır olsun.
    func preload() async

    /// Reklamı gösterir. Dönüş: kullanıcı ödülü hak etti mi (reklamı sonuna kadar izledi mi).
    @MainActor
    func present(from viewController: UIViewController) async -> Bool

    /// Son sunum turuna ait sağlayıcı-bağımsız kanıt zarfı (§9.4, 05-veri-modeli-api.md):
    /// server doğrulaması bu zarf + sağlayıcının S2S callback'i ile yapılır.
    func rewardProof() -> RewardProof?
}

/// Sağlayıcı-bağımsız ödül kanıtı zarfı.
struct RewardProof: Sendable {
    let provider: String                 // ör. "admob"
    let nonce: String                    // idempotency anahtarı (§5.2)
    let proofPayload: [String: String]   // sağlayıcıya özgü ek alanlar
}
```

Aşağıdaki `GADRewardedAd` kullanan kod **AdBridge/AdMob implementasyon örneğidir** (Faz 2'nin aktif sağlayıcısı); normatif sözleşme yukarıdaki protokoldür:

```swift
// RewardsKit/Sources/AdBridge/AdMobRewardedAdController.swift — AdBridge/AdMob implementasyon örneği
import GoogleMobileAds

@MainActor
final class AdMobRewardedAdController: RewardedAdProviding {
    private var loadedAd: GADRewardedAd?

    func preload() async {
        do {
            loadedAd = try await GADRewardedAd.load(
                withAdUnitID: RemoteConfig.rewardedAdUnitID,
                request: GADRequest())
            loadedAd?.serverSideVerificationOptions = currentSSVOptions() // §9.4
        } catch {
            loadedAd = nil
            Log.ads.error("rewarded load failed: \(error)")
        }
    }

    /// - Returns: kullanıcı ödülü hak etti mi (reklamı sonuna kadar izledi mi)
    func present(from viewController: UIViewController) async -> Bool {
        guard let ad = loadedAd else { return false }
        defer { loadedAd = nil; Task { await preload() } }   // bir sonraki için yeniden yükle
        return await withCheckedContinuation { continuation in
            var rewarded = false
            ad.present(fromRootViewController: viewController) { rewarded = true }
            ad.fullScreenContentDelegate = AdDismissRelay {   // kapanınca sonucu döndür
                continuation.resume(returning: rewarded)
            }
        }
    }

    func rewardProof() -> RewardProof? { /* SSV nonce + custom_data'dan üretilir (§9.4) */ nil }
}
```

Akış kuralları:

- **30 sn tamamlama şartı:** ödül yalnız sağlayıcının reward callback'i tetiklenirse (reklam sonuna kadar izlendiyse) verilir. Erken kapatma = ödül yok; `UnlockSheet` eski haliyle kalır, hak düşmez.
- Reklam gösterimi sırasında player sesi duraklatılır; dönüşte oynatma bağlamı korunur (04-player-engine.md).
- Reklam izleme sırasında app kill: ödülün S2S callback'i (§9.4) geldiyse server yine işler; istemci açılışta snapshot'tan güncel durumu görür.

### 9.4 Ödül doğrulama (SSV)

- **Client callback'ine güvenilmez.** Normatif kural sağlayıcı-bağımsızdır: ödül, reklam sağlayıcının **sunucudan sunucuya (S2S) imzalı callback'i** ile doğrulanır; istemci yalnız §9.3'teki kanıt zarfını (`RewardProof`: `{provider, nonce, proofPayload}`, bkz. 05-veri-modeli-api.md) iletir. Aktif sağlayıcı implementasyonu (AdMob): **server-side verification (SSV)** yapılandırılır — AdMob, ödülü backend endpoint'ine imzalı callback ile bildirir (`user_id` = backend userId, `custom_data` = hedef `episodeId` + nonce).
- Backend S2S callback imzasını doğrular, nonce ile idempotent işler (§5.2), unlock'u/coin grant'ini yazar ve cap sayacını artırır. İstemci ödül UI'ını iyimser gösterebilir ama kalıcı durum snapshot'tan gelir; S2S callback 10 sn içinde ulaşmazsa "Ödülün işleniyor" durumu gösterilir ve refresh'le çözülür.

### 9.5 Ad yoksa fallback

| Durum | Davranış |
|---|---|
| Reklam envanteri yok / yükleme başarısız | `UnlockSheet`'te reklam satırı devre dışı: "Şu an reklam yok — birazdan tekrar dene"; coin/VIP seçenekleri normal. Arka planda tek retry; satır durumu canlı güncellenir |
| Cap doldu | Satır devre dışı + "Yarın 5 yeni hak" |
| ATT izni yok | Reklam kişiselleştirilmemiş (NPA) olarak yine gösterilir; rewarded akış ATT'ye bağlanmaz |
| Çocuk/hassas kategori uyumu | AdMob içerik derecelendirme ayarları uygulanır (yasal inceleme Faz 2 başında) |

- ATT istemi `Onboarding`'de değer önerisinden sonra sorulur (kanon); AdMob başlatması ATT sonucundan bağımsız çalışır.
- Rewarded ads geliri VIP kullanıcıya gösterilmez ("reklamsız" ayrıcalığı); VIP zaten tüm bölümlere erişir, `OdulMerkezi` reklam kartı VIP'e gizlenir.

---

## 10. Fiyatlandırma deneyleri planı

Tüm deneyler 08-analitik-deney.md'deki feature-flag/remote-config altyapısıyla koşulur; burada monetizasyon deney kataloğu tanımlanır. Genel kurallar:

- Deney birimi: kullanıcı (userId); misafir→bağlı hesap geçişinde varyant korunur.
- Bekçi (guardrail) metrikleri her deneyde zorunlu: D1/D7 retention, refund oranı, crash-free, App Store yıldız ortalaması. Bekçi bozan varyant otomatik durdurulur.
- **App Store fiyat noktaları deney değişkeni DEĞİLDİR** (fiyat değişikliği tüm kullanıcılara yansır); deneyler bölüm coin fiyatı, coin adetleri/bonuslar, ücretsiz bölüm sayısı ve UI varyantları üzerinden yapılır — hepsi server kontrollüdür.

Deney kataloğu (öncelik sırasıyla):

| # | Deney | Varyantlar | Birincil metrik | Not |
|---|---|---|---|---|
| M1 | Ücretsiz bölüm sayısı | **5 vs 8 vs 10** | Payer conversion + D7 | Dizi bazında içerik ekibiyle koordineli; kilit her varyantta cliffhanger'a hizalanır |
| M2 | Bölüm coin fiyatı | 50 vs 75 vs 100 coin (dizi segmentine göre) | ARPDAU, unlock oranı | `unlockPrice` server'dan; UnlockSheet 409 akışı (§6.6) fiyat geçişini güvenli kılar |
| M3 | Paywall varyantı — UnlockSheet sıralaması | coin-önce (kontrol) vs VIP-önce | Payer conversion, VIP başlangıç oranı | Sheet düzeni §6.2'nin deneyle değişebilen tek parçası |
| M4 | Otomatik-unlock varsayılanı | kapalı (kontrol) vs ilk unlock sonrası önerilen | Bölüm/oturum, coin harcama | Şikâyet/iade oranı bekçisi kritik |
| M5 | İlk yükleme teklifi sunumu | banner (kontrol) vs banner+UnlockSheet vurgusu | İlk satın alma oranı | |
| M6 | Bonus merdiveni | §2.2 (kontrol) vs daha dik merdiven | Tier mix, ARPPU | Coin adetleri backend kataloğundan (§2.2) |
| M7 | Rewarded cap (Faz 2) | 5 vs 8 vs 10 | Payer conversion ↔ ad geliri dengesi, retention | adjoe verisi rewarded kullanıcının ~3x sık döndüğünü gösteriyor; cap'i salt gelirle optimize etme |

Ölçüm süresi: her deney minimum 2 hafta veya istatistiksel güç eşiğine ulaşana dek (hangisi geçse); ödeme metriklerinde gecikmeli dönüşüm (7 günlük atıf penceresi) hesaba katılır.

---

## 11. App Store Review uyumluluğu

### 11.1 Guideline 3.1.1 — tüm dijital içerik IAP ile

- Bölüm kilidi açma, coin ve VIP **yalnız IAP** ile satılır. Uygulama içinde harici ödeme yönlendirmesi, web mağaza linki, "webden daha ucuz" iması YOKTUR (Faz 1 kararı; harici link entitlement'ları ayrı hukuki değerlendirme konusudur ve bu dokümanın kapsamı dışındadır).
- Rewarded ads bir "ödeme atlatma" değildir; Apple'ın izin verdiği reklam-karşılığı-ödül modelidir. Reklam izleme karşılığı verilen içerik erişimi IAP zorunluluğunu ihlal etmez.
- Coin'ler gerçek paraya/hediyeye çevrilemez (kapalı devre, §2.1) — aksi kumar/ödül düzenlemelerini tetikler.

### 11.2 Fiyat gösterim kuralları

- Tüm fiyatlar StoreKit `displayPrice` ile, kullanıcının storefront para biriminde gösterilir; USD hardcode yasak (§4.2).
- İndirim iddiaları ("üstü çizili fiyat") yalnız gerçek bir referansa dayanır: ilk-yükleme 2x'te üstü çizili olan COIN adedidir, fiyat değil (§7.3). Yanıltıcı "normalde $X" fiyat karşılaştırması yapılmaz.
- Intro offer sunumunda "ilk hafta $3.99, sonra $5.99/hafta" kalıbı — hem intro hem normal fiyat birlikte, StoreKit verisinden.

### 11.3 Restore zorunluluğu

- "Satın Alımları Geri Yükle" butonu `VIPAbonelik`, `CoinMagazasi` ve `Ayarlar`'da bulunur (§4.6). Review'da abonelik satan her uygulamada aranan öğedir.

### 11.4 Abonelik açıklama zorunlulukları (Guideline 3.1.2)

Satın alma butonunun görünür yakınında ve zorlamasız fontta:

- Abonelik adı, süresi, dönem başına fiyat; intro varsa intro süre+fiyat ve sonrasındaki fiyat.
- "Abonelik, mevcut dönem bitmeden en az 24 saat önce iptal edilmediği sürece otomatik yenilenir. Yönetim ve iptal: App Store hesap ayarları." kalıbı.
- Kullanım Koşulları (EULA) ve Gizlilik Politikası linkleri hem uygulamada (`VIPAbonelik`, `CoinMagazasi`, `Ayarlar`) hem App Store metadata alanlarında.

### 11.5 Diğer review notları

- ATT istemi yalnız gerekçe metniyle ve `Onboarding`'de değer önerisi sonrası (kanon); reklam Faz 2'de geldiğinde `NSUserTrackingUsageDescription` metni hazır olmalı.
- Misafir hesapla satın alma serbesttir (Apple hesap zorunluluğu dayatmaz); ancak hesap silme özelliği (Ayarlar) zorunludur ve cüzdan sonuçları (coin kaybı) silme akışında açıkça bildirilir.
- Review ekibi kilitli içeriğe erişmek isteyebilir: App Review notlarına test hesabı + yeterli coin bakiyesi olan demo hesap eklenir.
- Sandbox ortamında tüm akışların çalışır olması (review sandbox'ta test eder): ürün listesi boş gelirse ekran çökmemelidir (§7.4).

---

## 12. Vergi ve bölgesel fiyatlandırma

- **App Store price tiers / fiyat noktaları:** baz fiyatlar ABD storefront'una göre kurulur; Apple diğer ~175 storefront'ta otomatik fiyat noktası eşlemesi ve (çoğu bölgede) vergi dahil fiyatlandırma uygular. KDV/satış vergisi Apple tarafından tahsil edilip düşüldükten sonra net gelir raporlanır; finans tarafında "brüt IAP ≠ net gelir" ayrımı raporlamada korunur (App Store komisyonu + bölgesel vergi farkları).
- **Tax category:** §3.3'teki kategori seçimi bölge bazında net geliri etkiler; lansman öncesi finans/hukuk onayı zorunlu.
- **Bölgesel satın alma gücü:** ABD birincil gelir pazarıdır (kategori gelirinin ~%49'u), ancak indirme büyümesi satın alma gücü düşük pazarlardan gelir. Kategori pratiği olarak lider uygulamaların fiyatları pazara göre yerelleştirdiği raporlanmaktadır — örneğin ReelShort'un **Filipinler**'de minimum yükleme eşiğini ve popüler paket seviyesini ABD'ye göre belirgin düşük tuttuğu tek kaynakta aktarılıyor (doğrulanmamış; **lansman öncesi App Store'dan doğrulanmalı**). ShortSeries için karşılığı:
  - Faz 1: Apple'ın otomatik bölgesel fiyat noktaları kullanılır; manuel bölge ayarı yapılmaz (EN-öncelikli, ABD ağırlıklı lansman).
  - TR/ES/PT ikinci dalgasıyla birlikte: seçili pazarlar (ör. Filipinler, Brezilya, Meksika, Türkiye) için Tier 1–2 paketlerde manuel düşük fiyat noktası + pazar bazlı "en popüler paket" rozeti değerlendirilir. Coin adetleri backend kataloğunda pazar bazlı ayarlanabilir olduğundan (§2.2) fiyat/coin oranı bölgeye göre kalibre edilebilir.
  - Bölgesel fiyat farkları arbitraj riski taşır (storefront değiştirme); coin bakiyesinin hesaba bağlı ve kapalı devre olması riski sınırlar, yine de fraud izlemede storefront değişim sinyali takip edilir (§5.3).
- **Fiyat artışları:** mevcut abonelerde Apple onay akışı devreye girer (§4.9); artış planları churn maliyetiyle birlikte 08-analitik-deney.md çerçevesinde modellenir.

---

## Ek: Faz kapsam özeti

| Yetenek | Faz |
|---|---|
| Coin paketleri, UnlockSheet, CoinMagazasi, VIP (3 plan + intro), restore, Server Notifications V2, purchased/earned ayrımı, ilk yükleme 2x, otomatik-unlock | **Faz 1** |
| Rewarded ads (AdMob, SSV, günlük cap), BildirimMerkezi'nde coin/kampanya bildirimleri | **Faz 2** |
| Bölgesel manuel fiyatlandırma dalgası, sezonluk teklif SKU'ları (`com.shortseries.offer.*`) | Faz 2+ (deney sonuçlarına bağlı) |

Fazlama ayrıntısı ve görev kırılımı: 09-yol-haritasi-tasklar.md.
