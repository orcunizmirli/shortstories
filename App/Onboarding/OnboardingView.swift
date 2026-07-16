import ContentKit
import DesignSystem
import ProfileKit
import SwiftUI

/// SS-064 — Onboarding'in İNCE SwiftUI kabuğu (02 §4.2). Tüm akış kararı `OnboardingModel`'dedir; bu
/// katman yalnız adımı çizer ve model metotlarını çağırır. Dark zemin (kanon §2), üstte ilerleme
/// noktaları, altta birincil CTA; tür ızgarası 3 sütun. Swipe ile adım geçişi YOK (02 §4.2 — yanlış
/// pozitif atlamayı önler).
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            OnboardingProgressDots(current: model.step)
                .padding(.top, DSSpacing.l)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColors.background.ignoresSafeArea())
        .task { model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .language: LanguageStepView(model: model)
        case .genre: GenreStepView(model: model)
        case .permissions: PermissionsStepView(model: model)
        }
    }
}

// MARK: - İlerleme noktaları (3 nokta)

private struct OnboardingProgressDots: View {
    let current: OnboardingModel.Step

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? DSColors.accent : DSColors.borderSubtle)
                    .frame(width: DSSpacing.s, height: DSSpacing.s)
            }
        }
        .accessibilityLabel("Adım \(current.rawValue + 1) / 3")
    }
}

// MARK: - Adım 1: dil

private struct LanguageStepView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            OnboardingHeader(
                title: "Dilini seç",
                subtitle: "Uygulama ve altyazı dilini sonradan Ayarlar'dan değiştirebilirsin."
            )
            VStack(spacing: DSSpacing.s) {
                ForEach(model.languageOptions) { language in
                    LanguageRow(
                        language: language,
                        isSelected: language == model.selectedLanguage
                    ) { model.selectLanguage(language) }
                }
            }
            Spacer(minLength: DSSpacing.l)
            DSButton("Devam") { model.advance() }
        }
    }
}

private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(verbatim: language.displayName)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DSColors.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(DSSpacing.m)
            .background(
                DSColors.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .strokeBorder(
                        isSelected ? DSColors.accent : DSColors.borderSubtle,
                        lineWidth: DSStroke.hairline
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(language.displayName)
    }
}

// MARK: - Adım 2: tür (atlanabilir)

private struct GenreStepView: View {
    let model: OnboardingModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.s), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            HStack(alignment: .top) {
                OnboardingHeader(
                    title: "Neleri seversin?",
                    subtitle: "Sana daha iyi öneriler sunalım. İstersen atlayabilirsin."
                )
                Spacer(minLength: DSSpacing.s)
                Button("Atla") { model.skipGenreStep() }
                    .font(DSTypography.bodyEmphasized)
                    .foregroundStyle(DSColors.textSecondary)
                    .accessibilityLabel("Tür seçimini atla")
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: DSSpacing.s) {
                    ForEach(model.genreOptions) { genre in
                        DSChip(
                            LocalizedStringKey(genre.name),
                            isSelected: model.isGenreSelected(genre.id)
                        ) { model.toggleGenre(genre.id) }
                    }
                }
            }
            Spacer(minLength: DSSpacing.s)
            DSButton("Devam") { model.advance() }
        }
    }
}

// MARK: - Adım 3: izinler (değer önerisi → bildirim → ATT)

private struct PermissionsStepView: View {
    let model: OnboardingModel

    var body: some View {
        switch model.permissionsPhase {
        case .valueProposition:
            OnboardingPrompt(
                systemImage: "bell.badge.fill",
                title: "Yeni bölüm çıkınca haber verelim",
                message: "Kaldığın diziden yeni bölüm yayınlanınca bildirelim, üstüne coin kazan.",
                primaryTitle: "Devam",
                primaryAction: { model.continueFromValueProposition() }
            )
        case .notificationPrePrompt:
            OnboardingPrompt(
                systemImage: "bell.fill",
                title: "Bildirimlere izin ver",
                message: "Yeni bölüm, kaldığın yerden devam ve coin ödülü hatırlatmaları için.",
                primaryTitle: "Bildirimleri Aç",
                primaryAction: { Task { await model.requestNotificationAuthorization() } },
                secondaryTitle: "Şimdi değil",
                secondaryAction: { model.deferNotifications() }
            )
        case .trackingPrePrompt:
            OnboardingPrompt(
                systemImage: "hand.raised.fill",
                title: "Daha isabetli öneriler",
                message: "İzin verirsen önerileri ve reklam deneyimini senin için daha isabetli yaparız.",
                primaryTitle: "Devam",
                primaryAction: { Task { await model.requestAppTracking() } },
                secondaryTitle: "Şimdi değil",
                secondaryAction: { model.deferTracking() }
            )
        }
    }
}

// MARK: - Ortak yapı taşları

private struct OnboardingHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
            Text(subtitle)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
        }
    }
}

/// Tek başlık + mesaj + birincil (+ opsiyonel ikincil) CTA'lı ön-izin/değer-önerisi ekranı.
private struct OnboardingPrompt: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: DSSpacing.l) {
            Spacer(minLength: DSSpacing.xxl)
            Image(systemName: systemImage)
                .font(DSTypography.display)
                .foregroundStyle(DSColors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: DSSpacing.l)
            DSButton(primaryTitle, action: primaryAction)
            if let secondaryTitle, let secondaryAction {
                DSButton(secondaryTitle, style: .secondary, action: secondaryAction)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
