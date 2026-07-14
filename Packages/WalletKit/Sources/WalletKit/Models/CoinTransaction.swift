import Foundation

/// Cüzdan ledger hareketi (05 §2.6). Tek bölüm kilidi earned+purchased karışık düşerse sunucu
/// **iki satır** döner (kese başına bir). `balanceAfter` yalnız gösterimdir; istemci bakiyeyi
/// bundan türetmez (05 §5.2). `type`/`bucket` bilinmeyen değere dayanıklıdır (05 §12 kural 4).
public struct CoinTransaction: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let type: TxnType
    /// İşaretli: kazanım +, harcama −.
    public let amount: Int
    public let bucket: Bucket
    public let balanceAfter: Int
    /// unlock → episodeId, iap → productId, mission → missionId.
    public let refId: String?
    public let note: String?
    public let createdAt: Date

    public init(
        id: String,
        type: TxnType,
        amount: Int,
        bucket: Bucket,
        balanceAfter: Int,
        refId: String?,
        note: String?,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.bucket = bucket
        self.balanceAfter = balanceAfter
        self.refId = refId
        self.note = note
        self.createdAt = createdAt
    }

    public enum TxnType: String, Sendable, Equatable, CaseIterable, Decodable, UnknownDecodable {
        case iapPurchase
        case episodeUnlock
        case checkInReward
        case missionReward
        case adReward
        case vipDailyBonus
        case refund
        case expiry
        case adminAdjust
        case unknown
    }

    public enum Bucket: String, Sendable, Equatable, CaseIterable, Decodable, UnknownDecodable {
        case purchased
        case earned
        case unknown
    }
}
