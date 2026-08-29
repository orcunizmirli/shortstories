import DesignSystem
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Davet-arkadaş (referral) ekranı (RWD-07) — ince SwiftUI katmanı: tüm karar `ReferralModel`'dedir.
/// Dark-first, DS token/bileşen; ham renk YOK. Davet kodu + paylaşım CTA'sı, davet sayaç şeridi, ve
/// kod-kullanma bölümü (server-otoriter redeem + kutlama/çakışma mesajları). Coin BAKİYESİ gösterilmez
/// (OdulMerkezi'nin işi); redeem başarısı "+N coin kazandın!" ile bildirilir.
public struct DavetMerkeziView: View {
    @State private var model: ReferralModel
    @State private var codeEntry = ""
    @State private var didCopy = false

    public init(model: ReferralModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DSColors.background)
            .onAppear { model.onAppear() }
            .sensoryFeedback(.success, trigger: model.redeemCelebration)
            // VoiceOver: redeem sonucu (başarı/çakışma/transport) dinamik eklenen Text'tir; SwiftUI onu
            // otomatik seslendirmez → durum değişince açıkça duyur (aksi halde ekran-okuyucu sonucu kaçırır).
            .onChange(of: model.redeemState) { _, _ in announceRedeemResult() }
            .onChange(of: model.redeemFailure) { _, _ in announceRedeemResult() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            DSStateView(.loading(skeleton: .shelf))
        case .failed:
            DSStateView(.error(message: "Davet bilgisi yüklenemedi") { Task { await model.retry() } })
        case .offline:
            DSStateView(.offline { Task { await model.retry() } })
        case .loaded:
            loadedContent
        }
    }

    // MARK: - Yüklenmiş içerik

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                inviteCodeCard
                statsStrip
                if showsRedeemArea {
                    redeemSection
                }
            }
            .padding(.horizontal, DSSpacing.l)
            .padding(.vertical, DSSpacing.xl)
        }
    }

    /// Redeem kartı gösterilir mi: kullanıcı kod kullanabiliyorsa VEYA gösterilecek bir sonuç (başarı/
    /// çakışma/transport hatası) varsa. Başarı sonrası `canRedeem` false olur ama kutlama mesajı görünür
    /// kalmalı (aksi halde tek başarı sinyali kaybolur).
    private var showsRedeemArea: Bool {
        model.canRedeem || model.redeemState != .idle || model.redeemFailure != nil
    }

    // MARK: - Davet kodu kartı (kod + paylaş + kopyala)

    private var inviteCodeCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionHeader("Davet Kodun")
            Text("Arkadaşların bu kodu girsin, ikiniz de coin kazanın.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
            Text(verbatim: model.inviteCode)
                .font(DSTypography.headingM)
                .foregroundStyle(DSColors.textPrimary)
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DSSpacing.m)
                .background(DSColors.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.card))
                .accessibilityLabel("Davet kodun: \(model.inviteCode)")
            HStack(spacing: DSSpacing.m) {
                DSButton("Paylaş", style: .coinCTA) { model.shareInvite() }
                    .disabled(!model.shareEnabled)
                DSButton(didCopy ? "Kopyalandı" : "Kodu Kopyala", style: .secondary) { copyCode() }
                    .disabled(!model.shareEnabled)
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // MARK: - Davet sayaç şeridi

    private var statsStrip: some View {
        HStack(spacing: DSSpacing.m) {
            statCell(value: "\(model.invitedCount)", label: "Davet")
            statCell(value: "\(model.status?.rewardedCount ?? 0)", label: "Ödüllü")
            statCell(value: "\(model.rewardPerReferral)", label: "Davet başına")
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(verbatim: value)
                .font(DSTypography.headingM)
                .foregroundStyle(DSColors.textPrimary)
                .monospacedDigit()
            Text(verbatim: label)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.m)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Kopyalama

    private func copyCode() {
        #if canImport(UIKit)
            UIPasteboard.general.string = model.inviteCode
        #endif
        didCopy = true
        // "Kopyalandı" geçici onaydır; kalıcı kalırsa ikinci kopyalama görsel/VoiceOver teyidi vermez.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    /// Redeem sonucunu VoiceOver'a duyurur (görsel Text ile aynı metin).
    private func announceRedeemResult() {
        guard let message = redeemMessage else { return }
        AccessibilityNotification.Announcement(message.text).post()
    }
}

// MARK: - Kod kullanma bölümü (server-otoriter redeem)

/// Redeem yüzeyi — aynı-dosya uzantısı: ana `body`'yi ince tutar. Kod girişi (native TextField, DS
/// token; DesignSystem'de metin alanı bileşeni yok) + server-otoriter "Kodu Kullan" + kutlama/çakışma.
/// Kod GİRİŞİ yalnız `canRedeem` iken; SONUÇ mesajı her durumda (başarı sonrası canRedeem false olsa da).
extension DavetMerkeziView {
    var redeemSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if model.canRedeem {
                DSSectionHeader("Davet Kodu Gir")
                Text("Seni davet eden arkadaşının kodunu gir.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                TextField("Örn. FRIEND-3K9P", text: $codeEntry)
                    .textFieldStyle(.plain)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(DSSpacing.m)
                    .background(DSColors.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.card))
                    .accessibilityLabel("Davet kodu")
                DSButton("Kodu Kullan", style: .coinCTA, isLoading: model.redeemState == .redeeming) {
                    Task { await model.redeem(codeEntry) }
                }
                .disabled(codeEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            redeemFeedback
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    @ViewBuilder
    private var redeemFeedback: some View {
        if let message = redeemMessage {
            Label(message.text, systemImage: message.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(message.isSuccess ? DSTypography.captionEmphasized : DSTypography.caption)
                .foregroundStyle(message.isSuccess ? DSColors.success : DSColors.warning)
                .accessibilityLabel(message.text)
        }
    }

    /// Gösterilecek redeem sonucu metni (başarı/çakışma/transport) — Text ve VoiceOver duyurusu ortak.
    private var redeemMessage: (text: String, isSuccess: Bool)? {
        switch model.redeemState {
        case let .credited(coins):
            return ("+\(coins) coin kazandın!", true)
        case let .conflict(reason):
            return (conflictText(reason), false)
        case .idle, .redeeming:
            break
        }
        if let failure = model.redeemFailure {
            return (failure == .offline ? "Bağlantı gerekli — tekrar dene" : "Kod kullanılamadı — tekrar dene", false)
        }
        return nil
    }

    private func conflictText(_ reason: ReferralConflict) -> String {
        switch reason {
        case .invalidCode: "Kod geçersiz"
        case .expired: "Kodun süresi dolmuş"
        case .selfReferral: "Kendini davet edemezsin"
        case .alreadyRedeemed: "Zaten bir davet kodu kullandın"
        }
    }
}
