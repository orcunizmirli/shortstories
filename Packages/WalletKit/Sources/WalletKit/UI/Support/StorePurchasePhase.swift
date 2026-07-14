import AppFoundation

/// Satın alma durum makinesi (06 §7.4 CoinMagazasi durumları, §4.9 edge case'ler). SAF: tek
/// giriş noktası `resolve(_:productID:)` `PurchaseFlowResult`'ı UI durumuna çevirir. Ekran
/// modelleri bu enum'u tutar; View durumu buradan türetir. İzole test edilir.
public enum StorePurchasePhase: Equatable, Sendable {
    /// Boşta — kartlar normal, dokunulabilir.
    case idle
    /// Seçili ürün için satın alma sürüyor — kart spinner'lı, diğerleri devre dışı.
    case purchasing(productID: String)
    /// Backend doğrulama geçti, kredi/entitlement yazıldı — bakiye animasyonu + başarı toast'ı.
    case success(productID: String)
    /// Ask to Buy / SCA (06 §4.9): "Onay bekleniyor, onaylanınca eklenecek".
    case pending(productID: String)
    /// Satın alma alındı ama backend kredisi gecikti (06 §4.3): "birazdan hesabında" banner'ı.
    case verificationPending(productID: String)
    /// Hata (StoreKit/ağ/wallet): "Tekrar dene" alert'i; teknik kod loglanır.
    case failed(productID: String)
    /// Sahte/doğrulanamayan makbuz (422): destek akışına yönlendir (06 §4.6).
    case invalidReceipt(productID: String)

    /// `PurchaseFlowResult` → faz. İptal (userCancelled) SESSİZDİR → `idle` (06 §7.5: hata yok).
    public static func resolve(_ result: PurchaseFlowResult, productID: String) -> StorePurchasePhase {
        switch result {
        case .completed:
            .success(productID: productID)
        case .verificationPending:
            .verificationPending(productID: productID)
        case .pending:
            .pending(productID: productID)
        case .cancelled:
            .idle
        case .invalidReceipt:
            .invalidReceipt(productID: productID)
        case .failed:
            .failed(productID: productID)
        }
    }

    /// Bir satın alma uçuşta mı — CTA/kart spinner'ı yalnız bunun için (06 §7.4).
    public var isPurchasing: Bool {
        if case .purchasing = self {
            true
        } else {
            false
        }
    }

    /// Yeni satın almayı engeller: uçuşta (`.purchasing`) VEYA Ask-to-Buy onayı bekliyor
    /// (`.pending`). Çift-satın alma koruması (06 §7.5) yalnız senkron `.purchasing` penceresini
    /// değil, asenkron pending-onay penceresini de kapsamalı — aksi halde aynı consumable için
    /// ikinci bir pending işlem başlatılıp onaylanınca çift ücret/kredi oluşur.
    public var preventsNewPurchase: Bool {
        switch self {
        case .purchasing, .pending:
            true
        case .idle, .success, .verificationPending, .failed, .invalidReceipt:
            false
        }
    }

    /// Satın alma sonucu banner'ının davranışı (metin View'da lokalize edilir). `nil` → banner yok
    /// (boşta/uçuşta). `.success` ve geçici bilgi (`.verificationPending`) otomatik kapanır; terminal
    /// hata/destek durumları (`.failed`/`.invalidReceipt`) KALICI kalır — kullanıcı elle kapatır,
    /// böylece "tekrar dene"/destek bilgisi 3sn'de silinmez (06 §4.6).
    public var banner: StorePurchaseBanner? {
        switch self {
        case .idle, .purchasing:
            nil
        case .success:
            StorePurchaseBanner(tone: .success, autoDismisses: true, requiresSupport: false)
        case .verificationPending:
            StorePurchaseBanner(tone: .warning, autoDismisses: true, requiresSupport: false)
        case .pending:
            StorePurchaseBanner(tone: .warning, autoDismisses: false, requiresSupport: false)
        case .failed:
            StorePurchaseBanner(tone: .danger, autoDismisses: false, requiresSupport: false)
        case .invalidReceipt:
            StorePurchaseBanner(tone: .danger, autoDismisses: false, requiresSupport: true)
        }
    }

    /// Uçuştaki ürün ID'si (yalnız o kart spinner gösterir).
    public var inFlightProductID: String? {
        if case let .purchasing(id) = self {
            id
        } else {
            nil
        }
    }

    /// Başarı fazındaki ürün (bakiye animasyonu tetiklendi).
    public var creditedProductID: String? {
        if case let .success(id) = self {
            id
        } else {
            nil
        }
    }
}

/// Satın alma sonucu banner'ının SAF davranış tarifi (06 §4.6/§7.4). Metin ekrana göre değişir
/// (coin/VIP) → View lokalize eder; bu tip yalnız ton + otomatik-kapanma + destek gereksinimini
/// taşır ve izole test edilir. Terminal hata/destek durumları kalıcıdır (auto-dismiss YOK).
public struct StorePurchaseBanner: Equatable, Sendable {
    /// Görsel ton (View DS renk token'ına eşler): olumlu / bilgi-uyarı / hata.
    public enum Tone: Equatable, Sendable {
        case success
        case warning
        case danger
    }

    public let tone: Tone
    /// `true` yalnız olumlu/geçici bilgi için (3sn sonra kapanır); terminal durumlar `false`.
    public let autoDismisses: Bool
    /// 422 doğrulanamayan makbuz gibi destek yönlendirmesi gereken terminal durum.
    public let requiresSupport: Bool

    public init(tone: Tone, autoDismisses: Bool, requiresSupport: Bool) {
        self.tone = tone
        self.autoDismisses = autoDismisses
        self.requiresSupport = requiresSupport
    }
}
