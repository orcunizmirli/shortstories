import AppFoundation

// MARK: - Görev merkezi (SS-112): türetimler + katalog/claim akışı

/// Görev merkezi mantığı (SS-112) — `OdulMerkeziModel` uzantısı: görev stored property'leri ana tipte
/// (`internal` erişimli) yaşar, bu uzantı türetimleri + claim/tazeleme akışını barındırıp ana tip
/// gövdesini ince tutar. Claim SERVER-OTORİTER + idempotent; katalog server-otoriter, ikincil yüzey.
public extension OdulMerkeziModel {
    /// Görev merkezi hücreleri (katalog + canlı overlay birleşimi; bilinmeyen tipler düşülü).
    var taskItems: [RewardTaskItem] {
        catalog.items(liveProgress: liveProgress)
    }

    /// Claim-edilebilir görev sayısı (Ödüller sekme rozeti, 07 §4.4).
    var claimableTaskCount: Int {
        catalog.claimableCount
    }

    /// Bu görev şu an claim ediliyor mu (satır spinner'ı).
    func isClaimingTask(_ id: String) -> Bool {
        claimingTaskID == id
    }

    /// Görev kataloğunu tazeler (07 §4.4: her açılışta + claim sonrası). Best-effort — hata son
    /// bilinen kataloğu korur ve ekran hatası ÜRETMEZ (görevler check-in'e göre ikincildir).
    internal func refreshTasks() async {
        do {
            let fresh = try await RewardTaskCatalog(
                tasks: taskCatalog.tasks(),
                rewardedAdEnabled: rewardedAdCardVisible // F2 gate: flag KAPALI iken watchAd düşer (SS-113)
            )
            applyLoadedCatalog(fresh)
        } catch {
            // İkincil yüzey: son bilinen katalog kalır, kullanıcı check-in'i görmeye devam eder.
        }
    }

    /// Tamamlanan görevin ödülünü talep eder (SS-112). Guard: yüklenmiş, başka claim yok (tek-seferde
    /// bir), görev VAR ve server `state == .claimable` (SERVER-otoriter — istemci ilerlemesi eşiği
    /// geçse bile sunucu onayı olmadan claim TETİKLENMEZ; 06 §, R6). Başarı → server bakiyesi + görev
    /// `.claimed` + haptic/animasyon + `mission_claim`. 409 → sessiz senkron (toast yok, kredi yok).
    /// Offline/hata → kredi YOK, satır-içi uyarı + retry. Çift-claim: `.claimed` sonrası guard → no-op.
    func claimTask(_ id: String) async {
        guard loadState == .loaded, claimingTaskID == nil,
              let task = catalog.tasks.first(where: { $0.id == id }),
              task.state == .claimable
        else {
            return
        }
        claimingTaskID = id
        taskClaimFailure = nil
        defer { claimingTaskID = nil }
        do {
            let result = try await rewardClaiming.claimTask(id: id)
            // SERVER-OTORİTER kredi: bakiye ve görev YALNIZ server yanıtından (optimistik DEĞİL).
            applyAuthoritativeBalance(result.coinBalance) // Fix 1: bayat akış bu krediyi ezemez
            markTaskClaimed(result.task) // Fix 4: yerel .claimed kaydı (bayat .claimable geri döndürmez)
            taskClaimCelebration += 1 // haptic + coin uçuş animasyonu (View tetikler)
            analytics.trackMissionClaim(
                missionID: result.task.id,
                coinReward: result.reward.coins,
                expiresAt: result.reward.expiresAt // SS-115 vade; nil ise expires_at atlanır
            )
            await refreshTasks() // Fix 3: claim sonrası katalog yeniden çekilir (07 §4.4)
        } catch let RewardClaimError.notClaimable(fresh) {
            // 409 MISSION_NOT_CLAIMABLE: görevi sessizce senkronla, hata gösterme (idempotent tekrar).
            // Kredi ZATEN düşmüş olabilir → başlığı otoriter cüzdandan tazele (Fix 2: bayat başlık kalmasın).
            markTaskClaimed(fresh)
            await applyAuthoritativeBalance(wallet.currentBalance())
        } catch {
            // Kredi VERİLMEZ; son bilinen katalog korunur, kullanıcı tekrar deneyebilir.
            taskClaimFailure = TaskClaimFailure(taskID: id, reason: Self.claimFailure(for: error))
        }
    }

    /// Görevi yerinde günceller ve `.claimed` ise oturum-claim kaydına ekler (Fix 4 eventual-consistency
    /// guard) — sonraki tazelemede server bayat `.claimable` döndürse bile satır `.claimed` tutulur.
    private func markTaskClaimed(_ task: RewardTask) {
        if task.state == .claimed {
            claimedTaskIDs.insert(task.id)
        }
        replaceTask(task)
    }

    /// Tek bir görevi katalogda yerinde günceller (claim yanıtı / 409 taze durumu). Kimlik yoksa no-op.
    private func replaceTask(_ task: RewardTask) {
        guard let index = catalog.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = catalog.tasks
        updated[index] = task
        catalog = RewardTaskCatalog(tasks: updated, rewardedAdEnabled: rewardedAdCardVisible)
    }

    /// Taze kataloğu uygular ve iki AYRI milestone atar (08 §3.5): ilerlemesi %50'yi İLK geçen görev için
    /// `mission_progress`, claim-edilebilir OLMAYANDAN olana geçen görev için `mission_complete`. İkisi de
    /// registry `mission_type` taksonomisinde karşılığı olan görevlerle sınırlıdır (linkAccount/watchAd
    /// atlanır). İlk yüklemede baseline yoktur → milestone atılmaz (kalıp: `checkin_streak_break`).
    /// `catalog` GÜNCELLENMEDEN önce karşılaştırılır.
    private func applyLoadedCatalog(_ rawFresh: RewardTaskCatalog) {
        // Fix 4 (eventual-consistency guard): yerel `.claimed` görevler, server bayat `.claimable`
        // döndürse bile `.claimed` tutulur → satır `.claimed`→`.claimable` GERİ DÖNMEZ ve aşağıdaki
        // newlyClaimable karşılaştırması `mission_complete`'i TEKRAR emit etmez.
        let fresh = reconcileClaimed(rawFresh)
        let baseline = catalogLoadedOnce ? catalog : nil
        for task in fresh.newlyHalfway(comparedTo: baseline) where task.kind.analyticsMissionType != nil {
            analytics.trackMissionProgress(missionID: task.id)
        }
        for task in fresh.newlyClaimable(comparedTo: baseline) {
            guard let missionType = task.kind.analyticsMissionType else { continue }
            analytics.trackMissionComplete(missionID: task.id, missionType: missionType)
        }
        catalog = fresh
        catalogLoadedOnce = true
    }

    /// Yerel olarak claim edilmiş (`claimedTaskIDs`) ama server hâlâ `.claimed` DEĞİL döndüren görevleri
    /// `.claimed`'e sabitler (Fix 4). Kayıt boşsa katalog değişmeden döner.
    private func reconcileClaimed(_ fresh: RewardTaskCatalog) -> RewardTaskCatalog {
        guard !claimedTaskIDs.isEmpty else { return fresh }
        let reconciled = fresh.tasks.map { task -> RewardTask in
            claimedTaskIDs.contains(task.id) && task.state != .claimed ? task.markingClaimed() : task
        }
        return RewardTaskCatalog(tasks: reconciled, rewardedAdEnabled: rewardedAdCardVisible)
    }
}
