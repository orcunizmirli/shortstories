import Foundation

/// En yakın son kullanma bildirimi (05 §2.5): OdulMerkezi/CoinMagazasi "X coin N gün içinde
/// sona erecek" bandı.
public struct ExpiryNotice: Sendable, Equatable, Decodable {
    public let amount: Int
    public let expiresAt: Date

    public init(amount: Int, expiresAt: Date) {
        self.amount = amount
        self.expiresAt = expiresAt
    }
}

/// Sunucunun otoritatif cüzdan anlık görüntüsü (05 §2.5). `GET /wallet`, `POST /wallet/unlock`
/// ve `POST /iap/verify` yanıtlarında birebir bu şema döner. İstemci bakiyeyi ASLA lokal
/// aritmetikle güncellemez; her mutasyon yeni snapshot getirir (05 §5.2). `version` monoton
/// artar ve out-of-order yanıt korumasını sağlar (05 §2.5: "version düşükse yanıtı at").
public struct WalletSnapshot: Sendable, Equatable, Decodable {
    public let balance: CoinBalance
    public let earnedExpiringSoon: ExpiryNotice?
    /// Sunucu-otoriter FEFO earned lotları (06 §2.5): her lot kendi `expiresAt`'iyle. Yaklaşan-vade
    /// (`EarnedCoinExpiryPlanner`) ve earned-önce harcama şeffaflığı bu lotlardan türetilir.
    ///
    /// WIRE TODO (05 §2.5): `GET /wallet` şu an YALNIZ tekil `earnedExpiringSoon` bandı döner;
    /// çok-lotlu `earnedBuckets` alanı sunucu sözleşmesine EKLENMELİDİR (kohort/TTL kuralları
    /// 06 §2.5 / 07). Alan gelene dek `decodeIfPresent` ile boş kalır (mevcut yanıtlar kırılmaz);
    /// eklendiğinde bu model değişmeden decode eder. Tekil bant, lot yoksa geriye-uyum için tutulur.
    public let earnedBuckets: [EarnedCoinBucket]
    public let firstTopUpEligible: Bool
    public let updatedAt: Date
    public let version: Int

    public init(
        balance: CoinBalance,
        earnedExpiringSoon: ExpiryNotice?,
        earnedBuckets: [EarnedCoinBucket] = [],
        firstTopUpEligible: Bool,
        updatedAt: Date,
        version: Int
    ) {
        self.balance = balance
        self.earnedExpiringSoon = earnedExpiringSoon
        self.earnedBuckets = earnedBuckets
        self.firstTopUpEligible = firstTopUpEligible
        self.updatedAt = updatedAt
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case purchasedCoins
        case earnedCoins
        case earnedExpiringSoon
        case earnedBuckets
        case firstTopUpEligible
        case updatedAt
        case version
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try CoinBalance(
            purchasedCoins: container.decode(Int.self, forKey: .purchasedCoins),
            earnedCoins: container.decode(Int.self, forKey: .earnedCoins)
        )
        earnedExpiringSoon = try container.decodeIfPresent(ExpiryNotice.self, forKey: .earnedExpiringSoon)
        earnedBuckets = try container.decodeIfPresent([EarnedCoinBucket].self, forKey: .earnedBuckets) ?? []
        firstTopUpEligible = try container.decode(Bool.self, forKey: .firstTopUpEligible)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        version = try container.decode(Int.self, forKey: .version)
    }
}
