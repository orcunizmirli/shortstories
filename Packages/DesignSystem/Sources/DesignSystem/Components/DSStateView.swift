import SwiftUI

/// Ortak durum bileşeni — 02 §3 sözleşmesinin tek API'si:
/// boş / hata / offline / yükleniyor. Ekranlar durum tablolarında bu
/// bileşene ekleme yapar, sözleşmeyi yeniden tanımlamaz.
public struct DSStateView: View {
    /// Boş durum CTA'sı — başlık ve aksiyon TEK değerde taşınır ki yalnız
    /// biri verilip butonun sessizce düşmesi temsil edilemez olsun.
    public struct EmptyAction {
        public let title: LocalizedStringKey
        public let handler: () -> Void

        public init(title: LocalizedStringKey, handler: @escaping () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    /// Loading skeleton varyantı (02 §3): raflar için `shelf`, kart
    /// ızgaraları için `grid`.
    public enum SkeletonVariant: Equatable, Sendable {
        /// Raf skeleton'u — başlık bloğu + yatay poster sırası.
        case shelf
        /// Kart ızgarası skeleton'u; kolon sayısı en az 1'e kırpılır
        /// (paketin sayısal clamp invariant'ı).
        case grid(columns: Int)
    }

    public enum Kind {
        /// Skeleton placeholder (spinner değil — 02 §3). 400 ms'den kısa
        /// yüklemelerde hiç göstermemek çağıranın sorumluluğudur.
        case loading(skeleton: SkeletonVariant)
        /// İllüstrasyon + tek cümle + (varsa) tek CTA; CTA kullanıcıyı
        /// içeriğe geri götürür (çoğunlukla Keşfet'e).
        case empty(
            message: LocalizedStringKey,
            systemImage: String,
            action: EmptyAction?
        )
        /// Kısa mesaj + "Tekrar Dene" — teknik detay içermez.
        case error(message: LocalizedStringKey, retry: () -> Void)
        /// Bağlantı yok durumu + "Tekrar Dene".
        case offline(retry: () -> Void)

        /// Varsayılan loading: raf skeleton'u (enum case'leri varsayılan
        /// ilişkili değer alamadığı için statik eşdeğer).
        public static var loading: Kind {
            .loading(skeleton: .shelf)
        }
    }

    private let kind: Kind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ kind: Kind) {
        self.kind = kind
    }

    /// Durum ikonunun SF Symbol adı; loading'de ikon yoktur (test kancası).
    var iconName: String? {
        switch kind {
        case .loading: nil
        case let .empty(_, systemImage, _): systemImage
        case .error: "exclamationmark.triangle"
        case .offline: "wifi.slash"
        }
    }

    /// Hata/offline retry aksiyonu (test kancası).
    var retryAction: (() -> Void)? {
        switch kind {
        case let .error(_, retry): retry
        case let .offline(retry): retry
        case .loading, .empty: nil
        }
    }

    /// Boş durum CTA'sı (test kancası).
    var emptyAction: EmptyAction? {
        switch kind {
        case let .empty(_, _, action): action
        case .loading, .error, .offline: nil
        }
    }

    /// Loading skeleton varyantı; loading dışı durumlarda nil (test kancası).
    var loadingSkeleton: SkeletonVariant? {
        switch kind {
        case let .loading(skeleton): skeleton
        case .empty, .error, .offline: nil
        }
    }

    public var body: some View {
        switch kind {
        case let .loading(skeleton):
            skeletonView(for: skeleton)
        case let .empty(message, _, action):
            messageState(text: message, actionTitle: action?.title, action: action?.handler)
        case let .error(message, retry):
            messageState(text: message, actionTitle: "Tekrar Dene", action: retry)
        case let .offline(retry):
            messageState(text: "Çevrimdışısın", actionTitle: "Tekrar Dene", action: retry)
        }
    }

    // MARK: - Mesajlı durumlar

    private func messageState(
        text: LocalizedStringKey,
        actionTitle: LocalizedStringKey?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DSSpacing.l) {
            if let iconName {
                Image(systemName: iconName)
                    .font(DSTypography.display)
                    .foregroundStyle(DSColors.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                DSButton(actionTitle, size: .compact, action: action)
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Skeleton

    private func skeletonView(for variant: SkeletonVariant) -> some View {
        Group {
            switch variant {
            case .shelf:
                shelfSkeleton
            case let .grid(columns):
                gridSkeleton(columns: columns)
            }
        }
        .padding(DSSpacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yükleniyor")
    }

    private var shelfSkeleton: some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            SkeletonBlock(animated: !reduceMotion)
                .frame(height: 20)
                .frame(maxWidth: 160)
            HStack(spacing: DSSpacing.m) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    SkeletonBlock(animated: !reduceMotion)
                        .aspectRatio(DSSeriesCard.posterAspectRatio, contentMode: .fit)
                }
            }
        }
    }

    private func gridSkeleton(columns: Int) -> some View {
        let columnCount = max(1, columns)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.m), count: columnCount),
            spacing: DSSpacing.m
        ) {
            ForEach(0 ..< columnCount * 2, id: \.self) { _ in
                SkeletonBlock(animated: !reduceMotion)
                    .aspectRatio(DSSeriesCard.posterAspectRatio, contentMode: .fit)
            }
        }
    }
}

/// Nabız animasyonlu skeleton bloğu; Reduce Motion açıkken sabittir.
private struct SkeletonBlock: View {
    let animated: Bool

    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: DSRadius.card)
            .fill(DSColors.surfaceElevated)
            .opacity(pulsing ? 0.45 : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
