import Foundation

/// Hesap silme talebi makbuzu (SS-133 / ONB-07 / App Store 5.1.1(v)). Bekleme süresi + geri-alma
/// penceresi KURALINI backend belirler; client yalnız GÖSTERİR (sözleşme sunucuda). Silme talebi
/// alındıktan sonra App yeni misafir oturumuna döner; kullanıcı pencere içinde tekrar giriş yaparsa
/// backend silmeyi iptal eder.
public struct AccountDeletionReceipt: Sendable, Equatable {
    /// Bu ana kadar kullanıcı yeniden giriş yaparak silmeyi geri alabilir (backend penceresi).
    /// `nil` ise anında ve geri alınamaz silme (pencere yok).
    public let undoDeadline: Date?
    /// Aktif abonelik App Store üzerinden AYRICA iptal edilmeli (ONB-07 zorunlu uyarı: hesap silme
    /// StoreKit aboneliğini iptal ETMEZ). Client bunu net gösterir.
    public let requiresStoreSubscriptionCancellation: Bool

    public init(undoDeadline: Date?, requiresStoreSubscriptionCancellation: Bool) {
        self.undoDeadline = undoDeadline
        self.requiresStoreSubscriptionCancellation = requiresStoreSubscriptionCancellation
    }

    /// Geri-alma penceresi sunuldu mu (UI banner gösterir). DİKKAT: pencere GEÇMİŞTE kalmış olabilir;
    /// "hâlâ geri alınabilir mi" için `isUndoWindowOpen(now:)` kullanılmalı.
    public var hasUndoWindow: Bool {
        undoDeadline != nil
    }

    /// Geri-alma penceresi hâlâ AÇIK mı (deadline gelecekte). Geçmiş/expired deadline'da (saat kayması
    /// veya bayat makbuz) yanıltıcı "şu tarihe kadar geri alabilirsin" mesajı gösterilmemeli.
    public func isUndoWindowOpen(now: Date = Date()) -> Bool {
        guard let undoDeadline else { return false }
        return undoDeadline > now
    }
}

/// Kişisel veri indirme talebi makbuzu (SS-133; KVKK/GDPR / App Store veri erişimi). Backend dışa
/// aktarımı hazırlar ve kullanıcıya (genelde e-posta ile) iletir; client talebi başlatır ve teyidi
/// gösterir.
public struct DataExportReceipt: Sendable, Equatable {
    /// Dışa aktarımın iletileceği maskeli e-posta ("j***@example.com"); backend bilinmiyorsa `nil`.
    public let deliveryEmailMasked: String?

    public init(deliveryEmailMasked: String?) {
        self.deliveryEmailMasked = deliveryEmailMasked
    }
}

/// Hesap silme + veri indirme talebi portu (SS-133, R8). ProfileKit TANIMLAR; App backend'e bağlar
/// (silme ve veri-dışa-aktarım uçları — sözleşme F0 sonunda diğer auth uçlarıyla donar). Ağ
/// gerektiren tek ProfileKit işlemidir (02 §4.14): spinner + hata durumu modelde.
public protocol AccountDeletionServicing: Sendable {
    /// Silme talebini başlatır; backend geri-alma penceresi + abonelik uyarısı kuralını döner.
    func requestDeletion() async throws -> AccountDeletionReceipt

    /// Kişisel verilerin indirilmesi için talep kaydı oluşturur (App Store veri erişimi zorunluluğu).
    func requestDataDownload() async throws -> DataExportReceipt
}
