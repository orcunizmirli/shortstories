import DesignSystem
import SwiftUI

/// `BildirimMerkezi` tekil liste satırı (02 §4.15): tip-bazlı ikon + başlık + gövde + göreli zaman +
/// okunmamış nokta. Dark-first, YALNIZ DS token (ham renk yok). Satırın tamamı tek VoiceOver öğesidir
/// (tip/başlık/gövde/zaman/okunma tek etikette birleşir); dokunuş + sil sarmalayıcı `List` tarafından
/// aksiyon olarak sunulur.
struct NotificationRow: View {
    let notification: AppNotification
    /// Göreli zaman referansı (test kancası; View `Date()` geçer).
    let now: Date

    /// Okunmamış nokta yalnız `isRead == false`'da görünür (02 §4.15 + snapshot-mantık testi).
    var showsUnreadDot: Bool {
        !notification.isRead
    }

    /// Satırın göreli zaman metni (saf; `NotificationRelativeTime`'a delege).
    var relativeTime: String {
        NotificationRelativeTime.string(for: notification.createdAt, relativeTo: now)
    }

    /// Birleşik VoiceOver etiketi: tip + başlık + gövde + zaman (+ okunmadıysa durum).
    var accessibilityLabel: String {
        var parts = [
            Self.typeLabel(for: notification.type),
            notification.title,
            notification.body,
            relativeTime
        ]
        if showsUnreadDot {
            parts.append("okunmadı")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.m) {
            icon
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: notification.title)
                    .font(DSTypography.bodyEmphasized)
                    .foregroundStyle(DSColors.textPrimary)
                    .lineLimit(2)
                Text(verbatim: notification.body)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: DSSpacing.s)
            trailing
        }
        .padding(.vertical, DSSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// İkon glyph'i sabit 32x32 frame'de çizilir; DS `headingM` ölçekli fonttur. AX4/AX5 Dynamic
    /// Type'ta glyph frame'i taşıp başlık sütununa binmesin diye ikonun Dynamic Type ölçeği
    /// erişilebilirlik-altı bir üst sınıra kapatılır (başlık/gövde TAM ölçeklenmeye devam eder;
    /// yalnız sabit-frame ikon sınırlanır — DSTypography.playerOverlay istisnasıyla aynı gerekçe).
    static let iconMaxDynamicTypeSize: DynamicTypeSize = .xxxLarge

    private var icon: some View {
        Image(systemName: Self.iconSystemName(for: notification.type))
            .font(DSTypography.headingM)
            .foregroundStyle(Self.iconTint(for: notification.type))
            .dynamicTypeSize(...Self.iconMaxDynamicTypeSize)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: DSSpacing.xs) {
            Text(verbatim: relativeTime)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
            if showsUnreadDot {
                Circle()
                    .fill(DSColors.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Tip → sunum (saf; test kancası)

    /// Tip-bazlı SF Symbol (02 §4.15 "ikon (tip bazlı)"). rawValue push tipiyle hizalı; `.unknown`
    /// jenerik zil (öğe düşmez — savunmacı tip kararı `NotificationType`'da).
    static func iconSystemName(for type: NotificationType) -> String {
        switch type {
        case .newEpisode: "play.rectangle.fill"
        case .continueWatching: "play.circle.fill"
        case .coinReward: "bitcoinsign.circle.fill"
        case .recommendation: "sparkles"
        case .reward: "gift.fill"
        case .campaign: "megaphone.fill"
        case .unknown: "bell.fill"
        }
    }

    /// İkon vurgusu: coin/ödül tipleri coin-gold, diğerleri marka accent (yalnız DS token).
    static func iconTint(for type: NotificationType) -> Color {
        switch type {
        case .coinReward, .reward: DSColors.coinGold
        default: DSColors.accent
        }
    }

    /// VoiceOver ön eki (tip adı) — İkon `accessibilityHidden` olduğundan tip bilgisi etikette taşınır.
    static func typeLabel(for type: NotificationType) -> String {
        switch type {
        case .newEpisode: "Yeni bölüm"
        case .continueWatching: "Devam et"
        case .coinReward: "Coin ödülü"
        case .recommendation: "Öneri"
        case .reward: "Ödül"
        case .campaign: "Kampanya"
        case .unknown: "Bildirim"
        }
    }
}
