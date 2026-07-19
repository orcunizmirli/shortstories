import Foundation

/// Sunucu-otoriter tekil earned coin grant lotu (06 §2.5; 05 §2.5). Her kazanım (check-in /
/// görev / rewarded ad) kendi `expiresAt`'i ile grant edilir; tüketim **FEFO** (en erken
/// expire olan lottan başlar). İstemci bu lotları YALNIZ gösterim + yaklaşan-vade türetimi
/// için tutar — bakiye ve düşüm otoritesi sunucudadır (05 §5.2; istemci aritmetik yapmaz).
public struct EarnedCoinBucket: Sendable, Equatable, Decodable {
    /// Bu lotta kalan earned coin (≥ 0).
    public let amount: Int
    /// Bu lotun yanma (expire) zamanı, UTC.
    public let expiresAt: Date

    public init(amount: Int, expiresAt: Date) {
        self.amount = amount
        self.expiresAt = expiresAt
    }
}

/// Yaklaşan-vade uyarısının türetilmiş özeti (06 §2.5 "7 gün içinde sona erecek X coin";
/// OdulMerkezi + CoinMagazasi bandı). Sunucunun tekil `ExpiryNotice`'inin çok-lotlu, eşik
/// yapılandırılabilir genellemesi. Saf `EarnedCoinExpiryPlanner` türevidir; istemci bunu
/// bakiye güncellemesi için KULLANMAZ, yalnız gösterir.
public struct UpcomingEarnedExpiry: Sendable, Equatable {
    /// Eşik penceresi içinde yanacak toplam earned coin.
    public let coins: Int
    /// Sayılan lotlar içinde EN ERKEN yanma zamanı (banda gösterilecek; "N gün" bundan türetilir).
    public let earliestExpiresAt: Date
    /// Katkı veren (eşik içi, süresi geçmemiş, coin > 0) lot sayısı.
    public let bucketCount: Int

    public init(coins: Int, earliestExpiresAt: Date, bucketCount: Int) {
        self.coins = coins
        self.earliestExpiresAt = earliestExpiresAt
        self.bucketCount = bucketCount
    }
}

/// FEFO harcama ön-izlemesinin tek satırı (06 §2.4/§2.5): earned porsiyon en erken expire
/// olan lottan başlayarak düşerken hangi lottan ne kadar çekileceğini UI'ya şeffaflaştırır.
public struct EarnedSpendLine: Sendable, Equatable {
    /// Bu lottan düşecek coin (> 0).
    public let coins: Int
    /// İlgili lotun yanma zamanı ("14 Tem'de yanacak 30 coin önce düşer").
    public let expiresAt: Date

    public init(coins: Int, expiresAt: Date) {
        self.coins = coins
        self.expiresAt = expiresAt
    }
}

/// Earned coin vadesi SAF mantığı (06 §2.5) — yan etkisiz, deterministik, `now` enjekte
/// edilebilir → izole test. Bakiye/kredi SERVER-otoriter; buradaki hiçbir fonksiyon bakiyeyi
/// mutasyona uğratmaz, yalnız sunucudan gelen lotlardan GÖSTERİM türevi üretir.
public enum EarnedCoinExpiryPlanner {
    /// Varsayılan yaklaşan-vade eşiği (06 §2.5: "7 gün içinde"). `earnedCoinTTLDays` gibi remote
    /// config değil; bu yalnız UYARI penceresidir ve çağrı başına override edilebilir.
    public static let defaultThresholdDays = 7
    public static let defaultThreshold = TimeInterval(defaultThresholdDays) * 86400

    /// Yaklaşan-vade uyarısı: `now`'dan itibaren `threshold` penceresi içinde yanacak earned
    /// coin toplamı + en erken yanma zamanı. Süresi GEÇMİŞ lotlar (`expiresAt <= now`) hariç
    /// (sunucu onları zaten `expire` ile düştü); pencere DIŞI lotlar (`expiresAt > now+threshold`)
    /// hariç; coin ≤ 0 lotlar sayılmaz. Uygun lot yoksa `nil` (bant çizilmez).
    ///
    /// - Parameters:
    ///   - buckets: Sunucudan gelen earned lotları (herhangi bir sırada).
    ///   - now: Enjekte edilen "şimdi" (izole test için).
    ///   - threshold: Uyarı penceresi (saniye); varsayılan 7 gün. Sınır dahil (`<= now+threshold`).
    public static func upcomingExpiry(
        buckets: [EarnedCoinBucket],
        now: Date,
        within threshold: TimeInterval = defaultThreshold
    ) -> UpcomingEarnedExpiry? {
        let cutoff = now.addingTimeInterval(threshold)
        let qualifying = buckets.filter {
            $0.amount > 0 && $0.expiresAt > now && $0.expiresAt <= cutoff
        }
        guard let earliest = qualifying.map(\.expiresAt).min() else { return nil }
        let coins = qualifying.reduce(0) { $0 + $1.amount }
        return UpcomingEarnedExpiry(
            coins: coins,
            earliestExpiresAt: earliest,
            bucketCount: qualifying.count
        )
    }

    /// Bucket toplama (06 §2.4): süresi GEÇMEMİŞ tüm earned lotlarının toplamı. Sunucunun
    /// `earnedCoins` bakiyesiyle mutabık olması beklenir; drift olursa gösterim yine lotlardan
    /// türer (istemci bakiyeyi lotlardan HESAPLAMAZ, yalnız kesişimi doğrular/gösterir).
    public static func totalUnexpired(buckets: [EarnedCoinBucket], now: Date) -> Int {
        buckets.reduce(0) { $0 + ($1.expiresAt > now ? max(0, $1.amount) : 0) }
    }

    /// FEFO sıralama: süresi geçmemiş lotlar, en erken expire önce (eşitlikte kararlı). Cüzdan
    /// detayı listesi ve harcama ön-izlemesi bu sırayı kullanır.
    public static func fefoOrder(_ buckets: [EarnedCoinBucket], now: Date) -> [EarnedCoinBucket] {
        buckets
            .filter { $0.expiresAt > now && $0.amount > 0 }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    /// Earned-önce harcama ŞEFFAFLIĞI (06 §2.4/§2.5): earned porsiyon FEFO ile hangi lotlardan
    /// düşer? Verilen `earnedAmount`'ı en erken expire olan lottan başlayarak böler (kısmi lot
    /// dahil). Süresi geçmiş lotlar hariç. Saf ÖN-İZLEMEdir; sunucu düşümü otoritatiftir.
    ///
    /// `earnedAmount`, `SpendPlan.earnedSpent` (earned-önce bölünmüş porsiyon) ile beslenir.
    public static func earnedSpendPreview(
        earnedAmount: Int,
        buckets: [EarnedCoinBucket],
        now: Date
    ) -> [EarnedSpendLine] {
        var remaining = max(0, earnedAmount)
        guard remaining > 0 else { return [] }
        var lines: [EarnedSpendLine] = []
        for bucket in fefoOrder(buckets, now: now) {
            guard remaining > 0 else { break }
            let take = min(remaining, bucket.amount)
            lines.append(EarnedSpendLine(coins: take, expiresAt: bucket.expiresAt))
            remaining -= take
        }
        return lines
    }
}

/// Yaklaşan-vade UYARISININ saf SUNUM türevi (SS-115 D1; 06 §2.5). CoinMagazasi başlığı (ve
/// ileride OdulMerkezi/Profil) bunu doğrudan çizer — görünürlük kararı + "N gün" + mesaj burada
/// izole test edilir; SwiftUI katmanı ince kalır. Vade SERVER-otoriterdir: bu tip bakiye/lot
/// HESAPLAMAZ, yalnız sunucudan gelen lotlardan/banttan gösterim türetir.
public struct EarnedExpiryWarning: Sendable, Equatable {
    /// Eşik penceresi içinde yanacak toplam earned coin (> 0).
    public let coins: Int
    /// En erken yanmaya kalan TAM gün (≥ 1; 24 saatten az → 1). "N gün içinde" bundan.
    public let daysRemaining: Int

    public init(coins: Int, daysRemaining: Int) {
        self.coins = coins
        self.daysRemaining = daysRemaining
    }

    /// Banda basılan Türkçe cümle (06 §2.5 "N gün içinde sona erecek X coin"). TEK kaynak: View
    /// verbatim çizer, test bunu doğrular. Türkçede sayıdan sonra çoğul eki yok → "1/3/7 gün".
    public var message: String {
        "\(daysRemaining) gün içinde \(coins) kazanılmış coin sona erecek"
    }

    /// Görünürlük + içerik kararı. ÖNCE çok-lotlu `buckets` türevi (FEFO, eşik-içi, süresi geçmiş
    /// hariç — `EarnedCoinExpiryPlanner`); lot yoksa (sunucu henüz `earnedBuckets` göndermiyor —
    /// 05 §2.5 WIRE TODO) tekil `notice` bandına düşer, o da aynı eşik/geçmiş filtresinden geçer.
    /// Uygun vade yoksa `nil` → bant çizilmez.
    public static func resolve(
        buckets: [EarnedCoinBucket],
        notice: ExpiryNotice?,
        now: Date,
        within threshold: TimeInterval = EarnedCoinExpiryPlanner.defaultThreshold
    ) -> EarnedExpiryWarning? {
        if let upcoming = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now, within: threshold) {
            return EarnedExpiryWarning(
                coins: upcoming.coins,
                daysRemaining: daysRemaining(until: upcoming.earliestExpiresAt, now: now)
            )
        }
        // Geriye-uyum: lot yok ama sunucu tekil bandı gönderdi. Eşik/geçmiş filtresi lotlarla aynı.
        guard let notice, notice.amount > 0 else { return nil }
        let interval = notice.expiresAt.timeIntervalSince(now)
        guard interval > 0, interval <= threshold else { return nil }
        return EarnedExpiryWarning(
            coins: notice.amount,
            daysRemaining: daysRemaining(until: notice.expiresAt, now: now)
        )
    }

    /// En erken yanmaya kalan tam gün — yukarı yuvarlama (pencere semantiği: "N gün İÇİNDE"),
    /// min 1 (24 saatten az kalsa bile "0 gün" gösterilmez).
    static func daysRemaining(until expiresAt: Date, now: Date) -> Int {
        let interval = expiresAt.timeIntervalSince(now)
        guard interval > 0 else { return 0 }
        return max(1, Int(ceil(interval / 86400)))
    }
}
