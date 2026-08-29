import AppFoundation
import Foundation
import RewardsKit

// RewardsKit `ReferralGateway` server-otoriter portunun canlı adaptörü (RWD-07, R8). Port RewardsKit'te
// tanımlı (tüketici); App onu `APIClient`'a (üretici) köprüler ve JSON ↔ SAF domain (`ReferralStatus`)
// eşlemesini yapar. RewardsKit ağ/JSON/UUID/timezone GÖRMEZ.
//
// TRANSPORT ayrıntıları (05 §9) adaptördedir: redeem POST'u `Idempotency-Key` (UUID v4) taşır → APIClient
// yanıtsız isteği AYNI anahtarla güvenle tekrarlar (server dedup). Para-etkili POST (05 §9 listesine eklenir).
//
// PREP-BEKLEYEN: canlı `/rewards/referral` endpoint'i + ürün/ekonomi kararı hazır olana dek bu adaptör
// `RewardsFlags.referralCard` KAPALI iken bağlanMAZ (composition `MockReferralGateway` verir).

// MARK: - Referral (GET /rewards/referral, POST /rewards/referral/redeem)

/// RewardsKit `ReferralGateway` → `APIClient`. Çakışmalar APIClient'ın yüzdürdüğü HTTP durum kodundan
/// eşlenir (kullanıcıya-görünür): 404 geçersiz, 410 süresi-dolmuş, 422 kendine-davet, 409 zaten-kullanılmış
/// (taze durumla senkron). NOT (prep): APIClient `error.code` yüzdürmediği için 422 kendine-davet ↔
/// idempotency-mismatch ayrımı belirsizdir; doğru key yönetiminde mismatch oluşmaz (05 §9) → 422 =
/// kendine-davet varsayılır. Canlı entegrasyonda endpoint çakışma-başına ayrık HTTP kodu döndürür.
struct APIReferralGateway: ReferralGateway {
    private let client: any APIClientProtocol
    private let makeIdempotencyKey: @Sendable () -> String

    init(
        client: any APIClientProtocol,
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func status() async throws -> ReferralStatus {
        try await client.send(ReferralStatusEndpoint()).referral
    }

    func redeem(code: String) async throws -> ReferralRedeemOutcome {
        do {
            return try await client.send(
                ReferralRedeemEndpoint(code: code, key: makeIdempotencyKey())
            ).outcome
        } catch AppError.network(.server(status: 404)) {
            return .conflict(.invalidCode)
        } catch AppError.network(.server(status: 410)) {
            return .conflict(.expired)
        } catch AppError.network(.server(status: 422)) {
            return .conflict(.selfReferral)
        } catch AppError.network(.server(status: 409)) {
            // Zaten bir kod kullanılmış: taze durumu BEST-EFFORT çek (transport hatasını yut). Taze GET
            // başarısız olsa da çakışma kesindir → `.alreadyRedeemed(nil)` döner; model çakışma mesajını
            // yine gösterir (transport hatasına düşmez, kullanıcı retry döngüsüne girmez), durum bir
            // sonraki yüklemede senkronlanır.
            return await .conflict(.alreadyRedeemed(try? status()))
        }
    }
}

private struct ReferralStatusEndpoint: Endpoint {
    typealias Response = ReferralWire

    var path: String {
        "/rewards/referral"
    }

    var method: HTTPMethod {
        .get
    }
}

private struct ReferralRedeemEndpoint: Endpoint {
    typealias Response = ReferralRedeemResultWire

    let code: String
    let key: String

    struct RequestBody: Encodable, Sendable {
        let code: String
    }

    var path: String {
        "/rewards/referral/redeem"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(code: code)
    }

    /// Idempotency key header ile taşınır (05 §9): yanıtsız redeem AYNI anahtarla güvenle tekrarlanır.
    var idempotencyKey: String? {
        key
    }
}

// MARK: - Wire ↔ domain eşlemeleri

/// Davet durumu zarfı (05 §4.7 `<state>`). Tanınmayan ek alanlar yutulur (05 §1 kural 10).
///
/// `inviteURL` HAM STRING olarak decode edilir (`URL?` DEĞİL): bozuk/hatalı-tipli bir `inviteURL`
/// KOZMETIK bir alandır (App `DeepLinkFactory.referralURL` ile fallback kurar) → tüm ekranı düşürMEMELİ.
/// `URL?` synthesized decode'u present-ama-bozuk stringde `DecodingError` fırlatır ve ekran `.failed`
/// olurdu; string-decode + `URL(string:)` lenient eşlemesi bozuk değeri `nil`'e düşürür (ekran yüklenir).
struct ReferralWire: Decodable, Sendable {
    let inviteCode: String
    let inviteURL: String?
    let invitedCount: Int
    let rewardedCount: Int
    let pendingCount: Int
    let rewardPerReferral: Int
    let maxReferrals: Int?
    let canRedeem: Bool

    var referral: ReferralStatus {
        ReferralStatus(
            inviteCode: inviteCode,
            inviteURL: inviteURL.flatMap(URL.init(string:)),
            invitedCount: invitedCount,
            rewardedCount: rewardedCount,
            pendingCount: pendingCount,
            rewardPerReferral: rewardPerReferral,
            maxReferrals: maxReferrals,
            canRedeem: canRedeem
        )
    }
}

/// Redeem başarı zarfı (05 §4.7 `{ reward, <state>, wallet }`). `ClaimedRewardWire` check-in adaptöründen
/// yeniden kullanılır. NOT: `wallet` DECODE EDİLMEZ — davet ekranı running-total göstermez (bakiye
/// OdulMerkezi'nin işi), yalnız kazanılan ödül (`reward.coins`) kullanılır. `wallet` alanını okumamak,
/// server'ın gönderdiği kısmi/eksik bir `wallet` objesinin başarılı krediyi decode-hatasına düşürmesini
/// de önler (tanınmayan alanlar zaten yutulur, 05 §1 kural 10). Referral streak DEĞİL → `isStreakBonus: false`.
struct ReferralRedeemResultWire: Decodable, Sendable {
    let reward: ClaimedRewardWire
    let referral: ReferralWire

    var outcome: ReferralRedeemOutcome {
        .credited(
            reward: reward.reward(isStreakBonus: false),
            referral: referral.referral
        )
    }
}
