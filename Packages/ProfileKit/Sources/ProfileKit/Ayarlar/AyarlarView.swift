import DesignSystem
import SwiftUI

/// `Ayarlar` ekranı (SS-131) — ince SwiftUI katmanı: tüm karar `AyarlarModel`'de. Gruplu liste
/// (Dil / Bildirimler / Oynatma / Hesap / Yasal). Dark-first, DS token/bileşen; ham renk yok.
/// Uygulama + altyazı dili AYRI seçilir (SS-161). Tercih değişimi anında modele gider (kalıcı).
public struct AyarlarView: View {
    @State private var model: AyarlarModel

    public init(model: AyarlarModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                languageSection
                notificationsSection
                playbackSection
                accountSection
                legalSection
            }
            .padding(DSSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .onAppear { model.onAppear() }
    }

    // MARK: - Dil (SS-161)

    private var languageSection: some View {
        section("Dil") {
            menuRow(title: "Uygulama Dili", value: model.appLanguage.displayName) {
                ForEach(model.availableAppLanguages) { language in
                    Button { model.selectAppLanguage(language) } label: { Text(verbatim: language.displayName) }
                }
            }
            divider
            menuRow(title: "Altyazı Dili", value: model.subtitleLanguage.displayName ?? "Kapalı") {
                ForEach(model.availableSubtitleLanguages) { language in
                    Button { model.selectSubtitleLanguage(language) } label: {
                        Text(subtitleLabel(language))
                    }
                }
            }
        }
    }

    private func subtitleLabel(_ language: SubtitleLanguage) -> String {
        language.displayName ?? "Kapalı"
    }

    // MARK: - Bildirimler

    private var notificationsSection: some View {
        section("Bildirimler") {
            toggleRow(title: "Bildirimler", isOn: primaryBinding)
            if model.notificationsPrimary {
                ForEach(NotificationCategory.allCases, id: \.self) { category in
                    divider
                    toggleRow(title: categoryTitle(category), isOn: categoryBinding(category))
                }
            }
        }
    }

    private func categoryTitle(_ category: NotificationCategory) -> LocalizedStringKey {
        switch category {
        case .newEpisode: "Yeni bölüm"
        case .continueReminder: "Devam hatırlatması"
        case .coinRewards: "Coin & ödül"
        case .recommendations: "Öneriler"
        }
    }

    // MARK: - Oynatma (SS-131/048)

    private var playbackSection: some View {
        section("Oynatma") {
            toggleRow(
                title: "Otomatik oynatma",
                subtitle: "Bölüm sonu otomatik geçiş",
                isOn: autoplayBinding
            )
            divider
            toggleRow(
                title: "Veri tasarrufu",
                subtitle: "Hücreselde 480p + prefetch durdur",
                isOn: dataSaverBinding
            )
        }
    }

    // MARK: - Hesap

    private var accountSection: some View {
        section("Hesap") {
            buttonRow(title: "Hesap bağla / yönet") { model.openAccountManagement() }
            divider
            buttonRow(title: "Çıkış yap") { model.requestSignOut() }
            divider
            buttonRow(title: "Hesabı sil", role: .destructive) { model.requestAccountDeletion() }
        }
    }

    // MARK: - Yasal

    private var legalSection: some View {
        section("Yasal") {
            buttonRow(title: "Kullanım Koşulları") { model.openLegalPage(.termsOfService) }
            divider
            buttonRow(title: "Gizlilik Politikası") { model.openLegalPage(.privacyPolicy) }
            divider
            buttonRow(title: "EULA") { model.openLegalPage(.eula) }
            divider
            buttonRow(title: "Açık kaynak lisansları") { model.openLegalPage(.openSourceLicenses) }
        }
    }

    // MARK: - Ortak yapı taşları

    private func section(
        _ title: LocalizedStringKey,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionHeader(title)
            VStack(spacing: 0) { rows() }
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DSColors.borderSubtle)
            .frame(height: DSStroke.hairline)
            .padding(.leading, DSSpacing.l)
    }

    private func toggleRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                }
            }
        }
        .tint(DSColors.accent)
        .padding(DSSpacing.l)
    }

    private func menuRow(
        title: LocalizedStringKey,
        value: String,
        @ViewBuilder menuItems: () -> some View
    ) -> some View {
        Menu(content: menuItems) {
            HStack(spacing: DSSpacing.m) {
                Text(title)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer(minLength: DSSpacing.s)
                Text(verbatim: value)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(DSSpacing.l)
        }
    }

    private func buttonRow(
        title: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: DSSpacing.m) {
                Text(title)
                    .font(DSTypography.body)
                    .foregroundStyle(role == .destructive ? DSColors.danger : DSColors.textPrimary)
                Spacer(minLength: DSSpacing.s)
                if role != .destructive {
                    Image(systemName: "chevron.right")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(DSSpacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings (View → model; tek yön kaynak modeldedir)

    private var primaryBinding: Binding<Bool> {
        Binding(get: { model.notificationsPrimary }, set: { model.setNotificationsPrimary($0) })
    }

    private func categoryBinding(_ category: NotificationCategory) -> Binding<Bool> {
        Binding(
            get: { model.isNotificationCategoryEnabled(category) },
            set: { model.setNotificationCategory(category, enabled: $0) }
        )
    }

    private var autoplayBinding: Binding<Bool> {
        Binding(get: { model.autoplayEnabled }, set: { model.setAutoplayEnabled($0) })
    }

    private var dataSaverBinding: Binding<Bool> {
        Binding(get: { model.dataSaverEnabled }, set: { model.setDataSaverEnabled($0) })
    }
}
