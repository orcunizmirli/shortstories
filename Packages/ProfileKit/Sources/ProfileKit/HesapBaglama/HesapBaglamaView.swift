import DesignSystem
import SwiftUI

/// Hesap bağlama ekranı (SS-132) — ince SwiftUI katmanı: tüm karar `HesapBaglamaModel` durum
/// makinesinde. Misafir → Apple (F1) / Google / e-posta (F2) bağlama; hepsi sağlayıcı-bağımsız TEK
/// akıştan geçer. Dark-first, DS token; ham renk yok. Butonlar modeli tetikler (ham `ASAuthorization`/
/// Google/e-posta girdisi akış portları arkasında). Çakışma (409) birleştirme diyaloğu; iptal sessiz,
/// hata "Tekrar Dene". App Store 4.8: Sign in with Apple birincil ve KORUNUR.
public struct HesapBaglamaView: View {
    @State private var model: HesapBaglamaModel
    @State private var email = ""
    @State private var password = ""

    public init(model: HesapBaglamaModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: DSSpacing.xl) {
            valueProp
            Spacer(minLength: DSSpacing.l)
            statusArea
            actions
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .confirmationDialog(
            "Bu kimlik başka bir hesaba bağlı",
            isPresented: conflictDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Mevcut Hesabıma Geç") { model.resolveConflictBySwitching() }
            Button("Vazgeç", role: .cancel) { model.cancelConflict() }
        } message: {
            Text(conflictMessage)
        }
    }

    // MARK: - Değer önerisi (ilerlemeyi kaybetme mesajı — 02 §4.13)

    private var valueProp: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(DSTypography.display)
                .foregroundStyle(DSColors.accent)
                .accessibilityHidden(true)
            Text("Hesabını Bağla")
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
            Text("Coin bakiyen, kilidini açtığın bölümler ve VIP'in güvende kalsın. Yeni cihazda kaldığın yerden devam et.")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DSSpacing.xxl)
    }

    // MARK: - Durum alanı (başarı / iptal / hata)

    @ViewBuilder
    private var statusArea: some View {
        switch model.state {
        case .linked:
            statusBanner(
                icon: "checkmark.seal.fill",
                tint: DSColors.success,
                text: "Hesabın bağlandı."
            )
        case .cancelled:
            statusBanner(
                icon: "info.circle.fill",
                tint: DSColors.textSecondary,
                text: "Bağlama iptal edildi. İstediğinde tekrar deneyebilirsin."
            )
        case let .failed(error):
            statusBanner(
                icon: "exclamationmark.triangle.fill",
                tint: DSColors.danger,
                text: errorMessage(error)
            )
        case .idle, .linking, .conflict, .switching:
            EmptyView()
        }
    }

    private func statusBanner(icon: String, tint: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: DSSpacing.m) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.l)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private func errorMessage(_ error: HesapBaglamaError) -> LocalizedStringKey {
        switch error {
        case .appleUnavailable: "Apple ile giriş tamamlanamadı. Lütfen tekrar dene."
        case .googleUnavailable: "Google ile giriş tamamlanamadı. Lütfen tekrar dene."
        case .emailUnavailable: "E-posta ile bağlama tamamlanamadı. Lütfen tekrar dene."
        case .linkFailed: "Hesabın bağlanamadı. Bağlantını kontrol edip tekrar dene."
        }
    }

    // MARK: - Aksiyonlar (Apple birincil; Google + e-posta yanında)

    private var actions: some View {
        VStack(spacing: DSSpacing.m) {
            appleButton
            googleButton
            emailSection
            Button("Şimdi Değil") { model.dismiss() }
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .buttonStyle(.plain)
        }
    }

    /// Sign in with Apple butonu — Apple-imzalı DS bileşeni (HIG beyaz stil; ham renk DS'te).
    /// Modeli tetikler; ham `ASAuthorization` buraya SIZMAZ. İlgili akış uçuşta (`inFlightProvider ==
    /// .apple`) spinner; yeniden-başlatılamaz durumlarda (`canStartLinking`) devre dışı.
    private var appleButton: some View {
        DSAppleSignInButton("Apple ile Devam Et", isLoading: model.inFlightProvider == .apple) {
            // Model kapısı (`canRestart`) tetiği ayrıca korur: uçuşta / çakışma / başarı NO-OP.
            model.startAppleLinking()
        }
        .disabled(!canStartLinking)
    }

    /// Google ile bağlama (F2) — DS ikincil buton (ham renk DS'te). Google SDK View'a SIZMAZ (port).
    private var googleButton: some View {
        DSButton("Google ile Devam Et", style: .secondary, isLoading: model.inFlightProvider == .google) {
            model.startGoogleLinking()
        }
        .disabled(!canStartLinking)
    }

    /// E-posta ile bağlama (F2) — e-posta + parola girdisi; OTP doğrulama alt akışı port arkasında
    /// (05 §4.2.1). Ham parola modelde tutulmaz (yalnız porta iletilir).
    private var emailSection: some View {
        VStack(spacing: DSSpacing.s) {
            emailField
            passwordField
            DSButton("E-posta ile Devam Et", style: .secondary, isLoading: model.inFlightProvider == .email) {
                model.startEmailLinking(email: email, password: password)
            }
            .disabled(!canStartLinking || !isEmailFormValid)
        }
    }

    private var emailField: some View {
        TextField("E-posta", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(DSTypography.body)
            .foregroundStyle(DSColors.textPrimary)
            .padding(DSSpacing.m)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private var passwordField: some View {
        SecureField("Parola", text: $password)
            .textContentType(.password)
            .font(DSTypography.body)
            .foregroundStyle(DSColors.textPrimary)
            .padding(DSSpacing.m)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // MARK: - Türetimler

    /// Model `canRestart` kapısının View aynası: yeni bağlama yalnız idle/benign-iptal/hata'dan
    /// başlar; uçuşta, çakışma kararı beklerken ve başarı sonrası butonlar devre dışı.
    private var canStartLinking: Bool {
        switch model.state {
        case .idle, .cancelled, .failed: true
        case .linking, .switching, .conflict, .linked: false
        }
    }

    /// E-posta butonu yalnız iki alan da dolu iken etkin (boş istek porta gitmez).
    private var isEmailFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var conflictMessage: String {
        guard case let .conflict(conflict) = model.state else { return "" }
        let base = "Bu hesabın kimliği \(conflict.existingAccountMasked). "
        return conflict.willDiscardGuestData
            ? base + "Mevcut hesabına geçersen bu cihazdaki misafir ilerlemen kaybolur."
            : base + "Mevcut hesabına geçebilir veya vazgeçebilirsin."
    }

    private var conflictDialogBinding: Binding<Bool> {
        Binding(
            get: {
                if case .conflict = model.state {
                    true
                } else {
                    false
                }
            },
            set: { presented in
                if !presented {
                    model.cancelConflict()
                }
            }
        )
    }
}
