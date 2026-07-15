import AppFoundation
import Observation

/// Hesap silme + veri talebi ekran modeli (SS-133; ONB-07 / App Store 5.1.1(v)). @Observable/@MainActor;
/// SwiftUI View ince kalır. Çift-onay (yıkıcı eylem): "Hesabımı Sil" → onay diyaloğu → silme talebi
/// portu (`AccountDeletionServicing`). Backend bekleme+geri-alma penceresi kuralını döner; client
/// gösterir. Bağımsız alt-akış: kişisel veri indirme talebi. Analitik: `account_delete_started/completed`
/// (02 §4.14). Silme sonrası oturum sıfırlama App'tedir (delegate).
///
/// Silme durum makinesi: `idle → confirming → deleting → {completed | failed}`. Onay diyaloğu
/// olmadan `confirmDeletion()` çağrısı NO-OP'tur (çift-onay kapısı). Başarısızlıkta `completed`
/// analitiği ÜRETİLMEZ (registry yalnız started/completed tanımlar).
@MainActor
@Observable
public final class HesapSilmeModel {
    // MARK: - Silme durumu

    public enum DeletionState: Equatable, Sendable {
        case idle
        /// Onay diyaloğu açık (ikinci adım) — çift-onay kapısı.
        case confirming
        /// Backend silme işlemde (spinner).
        case deleting
        /// Silme alındı/planlandı — geri-alma penceresi + abonelik uyarısı gösterilir.
        case completed(AccountDeletionReceipt)
        /// Silme başarısız — "Tekrar Dene".
        case failed(HesapSilmeError)

        var isBusy: Bool {
            if case .deleting = self {
                true
            } else {
                false
            }
        }
    }

    /// Bağımsız veri indirme alt-akışı (silme durumundan ayrı).
    public enum DataExportState: Equatable, Sendable {
        case idle
        case requesting
        case requested(DataExportReceipt)
        case failed

        var isBusy: Bool {
            if case .requesting = self {
                true
            } else {
                false
            }
        }
    }

    public private(set) var deletionState: DeletionState = .idle
    public private(set) var dataExportState: DataExportState = .idle

    // MARK: - Bağımlılıklar

    private let deletion: any AccountDeletionServicing
    private let analytics: any AnalyticsTracking
    private weak var delegate: (any HesapSilmeDelegate)?

    private var deletionTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    public init(
        deletion: any AccountDeletionServicing,
        analytics: any AnalyticsTracking,
        delegate: (any HesapSilmeDelegate)?
    ) {
        self.deletion = deletion
        self.analytics = analytics
        self.delegate = delegate
    }

    // MARK: - Testler için deterministik bekleme

    func pendingWork() async {
        await deletionTask?.value
        await exportTask?.value
    }

    // MARK: - Silme (çift-onay)

    /// 1. adım: "Hesabımı Sil" → onay diyaloğunu aç (henüz backend'e GİTMEZ, analitik YOK).
    public func requestDeletion() {
        guard case .idle = deletionState else { return }
        deletionState = .confirming
    }

    /// Onay diyaloğu iptal → başa dön.
    public func cancelDeletion() {
        guard case .confirming = deletionState else { return }
        deletionState = .idle
    }

    /// 2. adım: onaylandı → backend silme talebi. Yalnız `confirming`'den ilerler (çift-onay kapısı).
    public func confirmDeletion() {
        guard case .confirming = deletionState else { return }
        deletionState = .deleting
        analytics.track("account_delete_started", parameters: [:])
        deletionTask = Task { [weak self] in await self?.performDeletion() }
    }

    private func performDeletion() async {
        do {
            let receipt = try await deletion.requestDeletion()
            deletionState = .completed(receipt)
            analytics.track("account_delete_completed", parameters: [:])
            delegate?.hesapSilmeDidComplete(receipt)
        } catch {
            deletionState = .failed(.deletionFailed)
        }
    }

    /// Hata sonrası "Tekrar Dene" → onay diyaloğunu yeniden aç (çift-onay tekrar).
    public func retryDeletion() {
        guard case .failed = deletionState else { return }
        deletionState = .confirming
    }

    // MARK: - Veri indirme talebi (bağımsız)

    public func requestDataDownload() {
        guard !dataExportState.isBusy else { return }
        dataExportState = .requesting
        exportTask = Task { [weak self] in await self?.performDataDownload() }
    }

    private func performDataDownload() async {
        do {
            let receipt = try await deletion.requestDataDownload()
            dataExportState = .requested(receipt)
        } catch {
            dataExportState = .failed
        }
    }

    // MARK: - Navigasyon

    public func dismiss() {
        // Yıkıcı eylem uçarken (.deleting) ekran KAPANMAZ: kullanıcı 'Vazgeç' ile iptal ettiğini
        // sanmasın; geri-alınamaz silme arka planda tamamlanırken oturum sessizce sıfırlanmasın
        // (SS-133 / App Store 5.1.1(v)). Silme durum makinesinin tek meşgul durumu `.deleting`'dir.
        guard !deletionState.isBusy else { return }
        delegate?.hesapSilmeRequestsDismiss()
    }
}

/// Silme ekranının SAF hata sınıflandırması — ham `AppError` SIZMAZ; View tek cümle mesaj seçer.
public enum HesapSilmeError: Equatable, Sendable {
    case deletionFailed
}
