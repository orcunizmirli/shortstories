import DesignSystem
import SwiftUI

/// `BildirimMerkezi` ekranı (SS-144; NTF-04, 02 §4.15) — ince SwiftUI katmanı: tüm karar
/// `NotificationCenterModel`'de. Dikey liste: tip-bazlı ikon + başlık + gövde + göreli zaman +
/// okunmamış nokta; üstte "Tümünü okundu say". Durumlar: boş / yükleniyor (skeleton satırlar) /
/// hata-offline (cache'li liste + üst banner). Sola-kaydır → sil; satır dokunuşu route'u modele/
/// delegate'e iletir (App çözer, R2); son satır → `loadMore`.
///
/// KURALLAR: DiscoverKit/Route enum'u İMPORT EDİLMEZ (rota ham String modelde). Yalnız DS token
/// (ham renk yok). Erişilebilirlik: Dynamic Type (tüm font'lar text-style) + satır başına birleşik
/// VoiceOver etiketi.
public struct BildirimMerkeziView: View {
    @State private var model: NotificationCenterModel

    public init(model: NotificationCenterModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsOfflineBanner {
                DSOfflineBanner(onRetry: retry)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .onAppear { model.onAppear() }
    }

    // MARK: - Durum → görünür bölüm (saf; snapshot-mantık test kancası)

    /// Ana içerik bölgesinin hangi bölümü çizeceği (02 §4.15 durum tablosu). `list` yalnız gösterilecek
    /// bildirim varken; boş `errorWithCache`'te offline/hata TAM-EKRAN ayrımı `isOffline` ile yapılır
    /// (model ayrı "cache'siz hata" state tutmaz — `NotificationCenterModel` §LoadState notu).
    enum ContentSection: Equatable {
        case skeleton
        case empty
        case list
        case offline
        case error
    }

    static func contentSection(
        loadState: NotificationCenterModel.LoadState,
        hasNotifications: Bool,
        isOffline: Bool
    ) -> ContentSection {
        switch loadState {
        case .idle, .loading:
            .skeleton
        case .loaded:
            hasNotifications ? .list : .empty
        case .emptyLoaded:
            .empty
        case .errorWithCache:
            hasNotifications ? .list : (isOffline ? .offline : .error)
        }
    }

    /// Üst offline banner yalnız cache'li LİSTE gösterilirken görünür (boş offline'da tam-ekran
    /// `DSStateView.offline` çift banner göstermesin diye).
    static func showsOfflineBanner(section: ContentSection, modelShowsBanner: Bool) -> Bool {
        section == .list && modelShowsBanner
    }

    /// "Tümünü okundu say" yalnız okunmamış varken aktif (02 §4.15 + snapshot-mantık testi).
    static func isMarkAllReadEnabled(unreadCount: Int) -> Bool {
        unreadCount > 0
    }

    private var section: ContentSection {
        Self.contentSection(
            loadState: model.loadState,
            hasNotifications: !model.notifications.isEmpty,
            isOffline: model.showsOfflineBanner
        )
    }

    private var showsOfflineBanner: Bool {
        Self.showsOfflineBanner(section: section, modelShowsBanner: model.showsOfflineBanner)
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        switch section {
        case .skeleton:
            skeleton
        case .empty:
            DSStateView(.empty(message: "Henüz bildirimin yok", systemImage: "bell.slash", action: nil))
                .frame(maxHeight: .infinity)
        case .offline:
            DSStateView(.offline(retry: retry))
                .frame(maxHeight: .infinity)
        case .error:
            DSStateView(.error(message: "Bildirimler yüklenemedi", retry: retry))
                .frame(maxHeight: .infinity)
        case .list:
            list
        }
    }

    // MARK: - Liste (mark-all-read çubuğu + satırlar + sayfa footer'ı)

    private var list: some View {
        VStack(spacing: 0) {
            markAllReadBar
            listRows
        }
    }

    private var markAllReadBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button { Task { await model.markAllRead() } } label: {
                Text("Tümünü okundu say")
                    .font(DSTypography.captionEmphasized)
                    .foregroundStyle(markAllReadEnabled ? DSColors.accent : DSColors.textTertiary)
            }
            .disabled(!markAllReadEnabled)
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.s)
    }

    private var markAllReadEnabled: Bool {
        Self.isMarkAllReadEnabled(unreadCount: model.unreadCount)
    }

    private var listRows: some View {
        let now = Date()
        return List {
            ForEach(model.notifications) { notification in
                Button { handleTap(notification) } label: {
                    NotificationRow(notification: notification, now: now)
                }
                .buttonStyle(.plain)
                .listRowBackground(DSColors.background)
                .listRowInsets(EdgeInsets(
                    top: DSSpacing.xs,
                    leading: DSSpacing.l,
                    bottom: DSSpacing.xs,
                    trailing: DSSpacing.l
                ))
                .listRowSeparatorTint(DSColors.borderSubtle)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await model.delete(notification.id) }
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
                .onAppear { maybeLoadMore(after: notification) }
            }
            if model.isLoadingMore {
                loadingFooter
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var loadingFooter: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(DSColors.textSecondary)
            Spacer()
        }
        .listRowBackground(DSColors.background)
        .listRowSeparator(.hidden)
        .accessibilityLabel("Daha fazla yükleniyor")
    }

    // MARK: - Skeleton (02 §3: spinner değil, placeholder satırlar)

    private var skeleton: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 6, id: \.self) { _ in
                NotificationSkeletonRow()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, DSSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yükleniyor")
    }

    // MARK: - Etkileşim

    /// Satır dokunuşu: önce okundu işaretle (optimistik), sonra route'u modele ilet — model analitik
    /// atar + `route` dolu → delegate açar, boş → `Kesfet` fallback (02 §4.15; çözüm App'te, R2).
    private func handleTap(_ notification: AppNotification) {
        Task { await model.markRead(notification.id) }
        model.open(notification)
    }

    /// Son satır göründüğünde sonraki sayfayı çek (sonsuz scroll; çift-guard modelde).
    private func maybeLoadMore(after notification: AppNotification) {
        guard model.canLoadMore, notification.id == model.notifications.last?.id else { return }
        Task { await model.loadMore() }
    }

    private func retry() {
        Task { await model.load() }
    }
}

/// Yükleniyor durumu için tek skeleton satırı — gerçek satır düzenini taklit eder (ikon + iki metin
/// bloğu). Nabız animasyonu Reduce Motion açıkken durur (DSStateView skeleton deseniyle aynı). Yalnız
/// DS token; ham renk yok.
private struct NotificationSkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.m) {
            block
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                block
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                block
                    .frame(height: 12)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.m)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private var block: some View {
        RoundedRectangle(cornerRadius: DSRadius.card)
            .fill(DSColors.surfaceElevated)
            .opacity(pulsing ? 0.45 : 1)
    }
}
