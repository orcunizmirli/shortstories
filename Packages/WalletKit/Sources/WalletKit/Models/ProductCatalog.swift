/// StoreKit product ID şeması (06 §3.1): `com.shortseries.<grup>.<kimlik>`, versiyonsuz,
/// App Store'da kalıcı. Fiyat/coin adedi ID'ye GÖMÜLMEZ (ör. `coins.tier2`, `coins.500` değil)
/// — coin adetleri backend kataloğundan (`GET /wallet/packages`) gelir.
public enum ShortSeriesProduct {
    public static let coinTiers: [String] = (1 ... 6).map { "com.shortseries.coins.tier\($0)" }

    public static let vipWeekly = SubscriptionPlan.weekly.productID
    public static let vipMonthly = SubscriptionPlan.monthly.productID
    public static let vipYearly = SubscriptionPlan.yearly.productID

    public static var subscriptions: [String] {
        SubscriptionPlan.allCases.map(\.productID)
    }

    /// `Product.products(for:)` çağrısına verilecek tüm ID'ler.
    public static var all: [String] {
        coinTiers + subscriptions
    }
}
