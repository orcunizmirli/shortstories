import DesignSystem
import SwiftUI

/// `OdulMerkezi` (Ödüller sekmesi) ekranı (SS-110/111) — ince SwiftUI katmanı: tüm karar
/// `OdulMerkeziModel` + saf türetimlerdedir (`CheckInCycle`/`CheckInDayCell`). Dark-first, DS
/// token/bileşen; ham renk YOK. Coin bakiyesi başlığı, günlük check-in şeridi + claim, görev listesi
/// alanı (SS-112 doldurur), rewarded ad kartı alanı (F1'de flag ile gizli, SS-113).
///
/// Claim başarısı → haptic (SS-015 DS sözlüğü gelene dek SwiftUI native `.sensoryFeedback(.success)`)
/// + coin uçuş/kutlama animasyonu; ikisi de `model.claimCelebration` token'ıyla (server onayı SONRASI).
public struct OdulMerkeziView: View {
    @State private var model: OdulMerkeziModel
    @State private var celebrationScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: OdulMerkeziModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DSColors.background)
            .onAppear { model.onAppear() }
            .task { await model.observeUpdates() }
            .sensoryFeedback(.success, trigger: model.claimCelebration)
            .sensoryFeedback(.success, trigger: model.taskClaimCelebration)
            .onChange(of: model.claimCelebration) { _, _ in celebrate() }
            .onChange(of: model.taskClaimCelebration) { _, _ in celebrate() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            DSStateView(.loading(skeleton: .shelf))
        case .failed:
            DSStateView(.error(message: "Ödüller yüklenemedi") { Task { await model.retry() } })
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
                balanceHeader
                checkInSection
                missionSection
                if model.rewardedAdCardVisible {
                    rewardedAdCard // F1'de flag KAPALI → gizli (SS-113 F2)
                }
            }
            .padding(.horizontal, DSSpacing.l)
            .padding(.vertical, DSSpacing.xl)
        }
    }

    // MARK: - Coin bakiyesi başlığı (RewardsWalletReading portu)

    private var balanceHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Coin Bakiyen")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                DSCoinLabel(amount: model.coinBalance, size: .large)
                    .scaleEffect(celebrationScale)
            }
            Spacer()
            DSButton("Coin Al", style: .secondary, size: .compact) { model.openCoinStore() }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // MARK: - Günlük check-in (SS-111)

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionHeader("Günlük Ödül")
            if model.streakDays > 0 {
                Text("\(model.streakDays) günlük seri 🔥")
                    .font(DSTypography.captionEmphasized)
                    .foregroundStyle(DSColors.textSecondary)
            }
            calendarStrip
            claimControl
        }
    }

    private var calendarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) {
                ForEach(model.calendar) { cell in
                    dayCell(cell)
                }
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }

    private func dayCell(_ cell: CheckInDayCell) -> some View {
        VStack(spacing: DSSpacing.xs) {
            Text("Gün \(cell.day)")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
            Image(systemName: dayIcon(cell))
                .font(DSTypography.headingM)
                .foregroundStyle(dayTint(cell))
            Text(verbatim: "\(cell.coins)")
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(cell.status == .upcoming ? DSColors.textTertiary : DSColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, DSSpacing.s)
        .frame(width: 64)
        .background(dayBackground(cell), in: RoundedRectangle(cornerRadius: DSRadius.card))
        .overlay {
            if cell.status == .today {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .strokeBorder(DSColors.accent, lineWidth: DSStroke.hairline * 3)
            }
        }
        .opacity(cell.status == .upcoming ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(cell))
    }

    private func dayIcon(_ cell: CheckInDayCell) -> String {
        switch cell.status {
        case .claimed: "checkmark.circle.fill"
        case .today: cell.isBonus ? "star.circle.fill" : "gift.fill"
        case .upcoming: cell.isBonus ? "star" : "lock.fill"
        }
    }

    private func dayTint(_ cell: CheckInDayCell) -> Color {
        switch cell.status {
        case .claimed: DSColors.success
        case .today: DSColors.coinGold
        case .upcoming: DSColors.textTertiary
        }
    }

    private func dayBackground(_ cell: CheckInDayCell) -> Color {
        cell.status == .today ? DSColors.surfaceElevated : DSColors.surface
    }

    private func dayAccessibilityLabel(_ cell: CheckInDayCell) -> String {
        let state = switch cell.status {
        case .claimed: "alındı"
        case .today: "bugün, alınabilir"
        case .upcoming: "kilitli"
        }
        let bonus = cell.isBonus ? ", streak bonusu" : ""
        return "Gün \(cell.day), \(cell.coins) coin, \(state)\(bonus)"
    }

    @ViewBuilder
    private var claimControl: some View {
        if model.canClaimToday {
            DSButton(
                "Ödülü Al · \(model.todayReward) coin",
                style: .coinCTA,
                isLoading: model.isClaiming
            ) { Task { await model.claimToday() } }
        } else {
            Text("Bugünün ödülü alındı — yarın tekrar gel")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DSSpacing.s)
        }
        if let failure = model.claimFailure {
            Text(claimFailureMessage(failure))
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.warning)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func claimFailureMessage(_ failure: OdulMerkeziModel.ClaimFailure) -> LocalizedStringKey {
        switch failure {
        case .offline: "Bağlantı gerekli — tekrar dene"
        case .generic: "Ödül alınamadı — tekrar dene"
        }
    }

    // MARK: - Rewarded ad kartı alanı (F1'de gizli — SS-113 F2)

    private var rewardedAdCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionHeader("Reklam İzle, Coin Kazan")
            Text("Kısa bir reklam izle, coin kazan")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // MARK: - Kutlama animasyonu (Reduce Motion'da sabit; sensoryFeedback ayrı tetikte)

    private func celebrate() {
        guard !reduceMotion else { return } // Reduce Motion: haptic kalır, ölçek animasyonu düşer
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            celebrationScale = 1.25
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            celebrationScale = 1
        }
    }
}

// MARK: - Görev merkezi (SS-112): izleme/favori/paylaşım/bildirim görevleri + ilerleme + claim

/// Görev merkezi görünümü (SS-112) — aynı-dosya uzantısı: ana `body`'yi ince tutar. İlerleme
/// `DSProgressBar`; claim server-otoriter (buton yalnız `.claimable`), satır-içi hata + vade notu.
extension OdulMerkeziView {
    var missionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionHeader("Görevler")
            if model.taskItems.isEmpty {
                Text("Şu an aktif görev yok — yakında yenileri gelecek")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DSSpacing.s)
            } else {
                ForEach(model.taskItems) { item in
                    taskRow(item)
                }
            }
        }
    }

    private func taskRow(_ item: RewardTaskItem) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                Image(systemName: taskIcon(item.kind))
                    .font(DSTypography.headingM)
                    .foregroundStyle(taskIconTint(item.status))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(verbatim: item.title) // sunucudan lokalize — istemci yeniden lokalize ETMEZ
                        .font(DSTypography.bodyEmphasized)
                        .foregroundStyle(DSColors.textPrimary)
                    HStack(spacing: DSSpacing.s) {
                        DSCoinLabel(amount: item.rewardCoins)
                        if let note = item.expiryNote {
                            expiryLabel(note)
                        }
                    }
                }
                Spacer(minLength: DSSpacing.s)
                taskTrailing(item)
            }
            if item.status == .inProgress || item.status == .claimable {
                taskProgressRow(item)
            }
            if let failure = model.taskClaimFailure, failure.taskID == item.id {
                Text(claimFailureMessage(failure.reason))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .opacity(item.status == .claimed ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(taskAccessibilityLabel(item))
    }

    @ViewBuilder
    private func taskTrailing(_ item: RewardTaskItem) -> some View {
        switch item.status {
        case .claimable:
            DSButton(
                "Al · \(item.rewardCoins)",
                style: .coinCTA,
                size: .compact,
                isLoading: model.isClaimingTask(item.id)
            ) { Task { await model.claimTask(item.id) } }
        case .claimed:
            Label("Alındı", systemImage: "checkmark.circle.fill")
                .font(DSTypography.captionEmphasized)
                .labelStyle(.iconOnly)
                .foregroundStyle(DSColors.success)
                .accessibilityLabel("Alındı")
        case .locked:
            Image(systemName: "lock.fill")
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(DSColors.textTertiary)
        case .inProgress:
            EmptyView() // ilerleme çubuğu satırı durumu taşır
        }
    }

    private func taskProgressRow(_ item: RewardTaskItem) -> some View {
        HStack(spacing: DSSpacing.s) {
            DSProgressBar(progress: item.progressFraction, height: 6)
            Text(verbatim: "\(item.displayedProgress)/\(item.target)")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
                .monospacedDigit()
        }
    }

    private func expiryLabel(_ note: RewardTaskItem.ExpiryNote) -> some View {
        Text(note == .today ? "Bugün sona erer" : "Bu hafta sona erer")
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.warning)
    }

    private func taskIcon(_ kind: RewardTask.Kind) -> String {
        switch kind {
        case .watchMinutes: "play.circle.fill"
        case .favoriteSeries: "heart.fill"
        case .shareSeries: "square.and.arrow.up"
        case .enableNotifications: "bell.fill"
        case .linkAccount: "person.crop.circle.badge.checkmark"
        case .watchAd: "movieclapper.fill"
        case .unknown: "star.fill"
        }
    }

    private func taskIconTint(_ status: RewardTask.DisplayStatus) -> Color {
        switch status {
        case .claimable: DSColors.coinGold
        case .claimed: DSColors.success
        case .inProgress: DSColors.accent
        case .locked: DSColors.textTertiary
        }
    }

    private func taskAccessibilityLabel(_ item: RewardTaskItem) -> String {
        let state = switch item.status {
        case .claimable: "ödül alınabilir"
        case .claimed: "alındı"
        case .locked: "kilitli"
        case .inProgress: "\(item.displayedProgress) / \(item.target) ilerleme"
        }
        return "\(item.title), \(item.rewardCoins) coin, \(state)"
    }
}
