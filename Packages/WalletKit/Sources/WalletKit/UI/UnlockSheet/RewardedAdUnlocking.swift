import AppFoundation
import Foundation

/// UnlockSheet'in "reklam izle, bölümü aç" satırını besleyen WALLETKIT-YEREL port (SS-114). WalletKit
/// RewardsKit'i (ve reklam SDK'sını) İMPORT ETMEZ (R2 feature izolasyonu) — App kompozisyon kökü canlı
/// `RewardsKit.RewardedAdService`'i bu porta bir adaptörle bağlar (kalıp: `WalletGateway`). Test/preview
/// için `FakeRewardedAdUnlocking` enjekte edilir.
///
/// PARA GÜVENLİĞİ (06 §9, R6): SERVER-OTORİTER. İstemci cap SAYMAZ, kilit AÇMAZ, ödül KREDİLEMEZ —
/// `remaining`/`resetsAt`/`dailyCap` ve unlock kararı server+config'ten gelir; UnlockSheet yalnız GÖSTERİR
/// ve `watchAdToUnlock` sonucunu uygular. VIP reklamsızlığı + A/B kolu + `ads.rewarded_enabled` bayrağı
/// App adaptöründe `availability`'den ÖNCE uygulanır (VIP'e reklam SDK'sı yoklanmaz, zorunlu-reklam yok).
public protocol RewardedAdUnlocking: Sendable {
    /// Ön-yükleme (yüzey görünmeden önce). VIP'e adaptör NO-OP'lar (reklam init'i yok, reklamsızlık).
    func preload() async

    /// Yüzey görünürlük kararı (bayrak × fill × cap × VIP × A/B). App RewardsKit `RewardedAdAvailability`'sini
    /// bu WalletKit-yerel karara köprüler; `dailyCap` config'ten (SS-024) satır metnine ("Bugün N/M") enjekte edilir.
    func availability() async -> RewardedAdUnlockAvailability

    /// Reklamı gösterir ve 30 sn tamamlanırsa server ad-unlock'unu tetikler. Sonuç SERVER-OTORİTERdir
    /// (istemci kredi vermez); `episodeID` UnlockSheet hedefidir.
    func watchAdToUnlock(episodeID: EpisodeID) async -> RewardedAdUnlockResult
}

/// UnlockSheet reklam satırının görünürlük/eylem durumu (06 §6.2 #4 / §9.2/§9.5). SAF, `Equatable` —
/// View doğrudan çizer, model izole test eder. `remaining`/`dailyCap` yalnız GÖSTERİM içindir (server saymaz).
public enum RewardedAdUnlockAvailability: Sendable, Equatable {
    /// Reklam hazır + hak var → satır görünür + etkin. `remaining`/`dailyCap` biliniyorsa "Bugün N/M hak kaldı"
    /// (server bildirmediyse sayı gösterilmez, satır etkin kalır).
    case available(remaining: Int?, dailyCap: Int?)
    /// Günlük cap doldu (server `remaining <= 0` / 429) → satır GÖRÜNÜR ama DEVRE DIŞI ("Yarın M yeni hak").
    /// Tasarım gereği ödemeye dönüşüm baskısıdır (06 §9.2). `resetsAt` server'dan (opsiyonel).
    case capReached(resetsAt: Date?, dailyCap: Int?)
    /// Satır hiç render EDİLMEZ: bayrak kapalı / fill yok / VIP / A/B kontrol kolu (06 §9.5, App adaptörü çözer).
    case hidden

    /// Satır render edilir mi (gizli DEĞİL). `hidden` dışında her durum görünür.
    public var isVisible: Bool {
        if case .hidden = self {
            false
        } else {
            true
        }
    }

    /// Kullanıcı şu an reklam izleyebilir mi (yalnız `available`). `capReached` görünür ama devre dışıdır.
    public var isActionable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }

    /// "Bugün N/M hak kaldı" göstergesi — yalnız `available` + hem `remaining` hem `dailyCap` biliniyorsa.
    public var remainingIndicator: (remaining: Int, dailyCap: Int)? {
        if case let .available(remaining, dailyCap) = self, let remaining, let dailyCap {
            (remaining, dailyCap)
        } else {
            nil
        }
    }
}

/// Reklam-ile-aç akışının inline geri bildirimi (SS-114 / 06 §9.5). View lokalize eder; model semantik
/// taşır. Erken kapatma ödül-yok olduğu için sessizdir (kullanıcı seçimi) → bu tip taşınmaz.
public enum AdWatchError: Equatable, Sendable {
    /// Doldurma yok / gösterim hatası → "Şu an reklam yok, birazdan tekrar dene" (satır etkin kalır, retry).
    case temporarilyUnavailable
    /// Server kanıtı reddetti (SSV, 06 §9.4) → "Ödül doğrulanamadı" (kilit açılmaz).
    case rewardRejected
}

/// İzle→unlock akışının SERVER-OTORİTER sonucu (SS-114). UnlockSheet bu sonuca göre UI'ı günceller;
/// `unlocked` → kilit açılır + reklam sonrası KESİNTİSİZ oynatma (coin unlock ile aynı akış). Erken
/// kapatma / fill yok / hata / red → ödül YOK, hak düşmez.
public enum RewardedAdUnlockResult: Sendable, Equatable {
    /// Server SSV doğruladı → kilit açıldı. `remainingToday` = işlem sonrası kalan hak (server; opsiyonel).
    case unlocked(remainingToday: Int?)
    /// Kullanıcı reklamı erken kapattı → ödül YOK, hak düşmez, satır olduğu gibi kalır (06 §9.3).
    case dismissedEarly
    /// Gösterilecek reklam yoktu → ödül YOK ("Şu an reklam yok, birazdan tekrar dene", 06 §9.5).
    case noFill
    /// Gösterim/transport hatası → ödül YOK.
    case failed
    /// Günlük cap doldu (429) → ödül YOK; satır capReached'e (devre dışı) geçer. `resetsAt` server'dan.
    case capReached(resetsAt: Date?)
    /// Server kanıtı reddetti (SSV, 06 §9.4) → ödül YOK, kilit açılmaz.
    case rewardRejected
}
