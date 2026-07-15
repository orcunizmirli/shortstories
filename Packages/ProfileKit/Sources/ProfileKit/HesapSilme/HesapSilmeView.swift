import DesignSystem
import Foundation
import SwiftUI

/// Hesap silme + veri talebi ekranı (SS-133; ONB-07 / App Store 5.1.1(v)) — ince SwiftUI katmanı:
/// tüm karar `HesapSilmeModel`'de. Dark-first, DS token; yıkıcı eylem `DSColors.danger` ile. Çift-onay:
/// buton → onay diyaloğu → silme. Silmeden ÖNCE coin/VIP geri ödenmez uyarısı (ONB-07 KC2). Bağımsız
/// "verilerimi indir" girişi. Geri-alma penceresi + abonelik uyarısı silme sonrası gösterilir.
public struct HesapSilmeView: View {
    @State private var model: HesapSilmeModel

    public init(model: HesapSilmeModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                switch model.deletionState {
                case let .completed(receipt):
                    completedState(receipt)
                default:
                    warningSection
                    dataExportSection
                    deletionSection
                }
            }
            .padding(DSSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .confirmationDialog(
            "Hesabını kalıcı olarak silmek üzeresin",
            isPresented: confirmDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Hesabı Sil", role: .destructive) { model.confirmDeletion() }
            Button("Vazgeç", role: .cancel) { model.cancelDeletion() }
        } message: {
            Text("Bu işlem geri alınamaz. Kalan coin ve VIP hakkın geri ödenmez.")
        }
    }

    // MARK: - Uyarı (silmeden ÖNCE — ONB-07 KC2)

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text("Hesabını Sil")
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
            bullet("Kalan coin bakiyen ve VIP hakkın geri ödenmez.")
            bullet("Aktif aboneliğini App Store > Abonelikler'den ayrıca iptal etmelisin — hesap silme aboneliği durdurmaz.")
            bullet("İzleme geçmişin, favorilerin ve satın alımların kalıcı olarak silinir.")
        }
        .padding(DSSpacing.l)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Veri indirme talebi (bağımsız)

    private var dataExportSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionHeader("Verilerin")
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                Text("Silmeden önce kişisel verilerinin bir kopyasını isteyebilirsin.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                dataExportControl
            }
            .padding(DSSpacing.l)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        }
    }

    @ViewBuilder
    private var dataExportControl: some View {
        switch model.dataExportState {
        case .idle:
            DSButton("Verilerimi İndir", style: .secondary, size: .compact) { model.requestDataDownload() }
        case .requesting:
            DSButton("Verilerimi İndir", style: .secondary, size: .compact, isLoading: true) {}
        case let .requested(receipt):
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DSColors.success)
                    .accessibilityHidden(true)
                Text(exportConfirmation(receipt))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Talep gönderilemedi.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.danger)
                DSButton("Tekrar Dene", style: .secondary, size: .compact) { model.requestDataDownload() }
            }
        }
    }

    private func exportConfirmation(_ receipt: DataExportReceipt) -> String {
        if let email = receipt.deliveryEmailMasked {
            "Talebin alındı. Hazır olunca \(email) adresine göndereceğiz."
        } else {
            "Talebin alındı. Hazır olunca sana bildireceğiz."
        }
    }

    // MARK: - Silme aksiyonu (çift-onay)

    private var deletionSection: some View {
        VStack(spacing: DSSpacing.m) {
            destructiveButton
            Button("Vazgeç") { model.dismiss() }
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .buttonStyle(.plain)
                .disabled(isDeleting) // silme uçarken ekran kapatılamaz (yıkıcı eylem, SS-133)
            if case .failed = model.deletionState {
                Text("Hesabın silinemedi. Bağlantını kontrol edip tekrar dene.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, DSSpacing.s)
    }

    /// Yıkıcı CTA — DS `.destructive` stili (danger zemin + beyaz metin, ham renk DS'te). `isLoading`
    /// silme uçarken spinner gösterir ve butonu devre dışı bırakır (ayrı isDeleting guard gerekmez).
    private var destructiveButton: some View {
        DSButton("Hesabımı Kalıcı Olarak Sil", style: .destructive, isLoading: isDeleting) {
            if case .failed = model.deletionState {
                model.retryDeletion()
            } else {
                model.requestDeletion()
            }
        }
    }

    // MARK: - Tamamlandı (geri-alma penceresi + abonelik uyarısı)

    private func completedState(_ receipt: AccountDeletionReceipt) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(DSColors.success)
                    .accessibilityHidden(true)
                Text("Silme talebin alındı")
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.textPrimary)
            }
            if let deadline = receipt.undoDeadline, receipt.isUndoWindowOpen() {
                Text(undoText(deadline))
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
            } else {
                // Geçmiş/expired deadline → yanıltıcı geri-alma mesajı gösterme (silme sürüyor).
                Text("Hesabın ve kişisel verilerin siliniyor.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
            }
            if receipt.requiresStoreSubscriptionCancellation {
                bullet("Aktif aboneliğin App Store > Abonelikler'den ayrıca iptal edilmelidir.")
            }
        }
        .padding(DSSpacing.l)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // MARK: - Türetimler

    private var isDeleting: Bool {
        if case .deleting = model.deletionState {
            true
        } else {
            false
        }
    }

    private var confirmDialogBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirming = model.deletionState {
                    true
                } else {
                    false
                }
            },
            set: { presented in
                if !presented {
                    model.cancelDeletion()
                }
            }
        )
    }

    private func undoText(_ deadline: Date) -> String {
        "Fikrini değiştirirsen \(Self.deadlineText(deadline)) tarihine kadar "
            + "tekrar giriş yaparak silmeyi geri alabilirsin."
    }

    private static func deadlineText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
