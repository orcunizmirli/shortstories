import Foundation
import SwiftData

/// Yerel şemanın ilk sürümü (03 §9: `VersionedSchema` + `SchemaMigrationPlan` gün birinden
/// kurulur). Her şema değişikliğinde yeni bir `VersionedSchema` eklenir ve
/// `PersistenceMigrationPlan`'a bir stage tanımlanır.
///
/// **Migration kapsamı (05 §3.2):** migration YALNIZ kullanıcı verisi entity'leri
/// (`WatchProgressEntity`, `FavoriteEntity`) için yazılır. Cache entity'leri
/// (`CachedSeriesEntity`, `CachedEpisodeListEntity`, `FeedSnapshotEntity`,
/// `CachedAssetRecordEntity`) yeniden üretilebilir olduğundan migrate EDİLMEZ —
/// `payloadSchemaVersion` uyumsuzluğunda okuma anında sessizce silinir (bkz. `CatalogCacheStore`).
///
/// **Cache kolon eklemeleri (WP-F1-G OPT-2):** cache entity'lerine EKLENEN alanlar
/// (ör. `sizeBytes`) `= 0` gibi bir default DEĞER taşır → SwiftData bunu *lightweight*
/// migration olarak eski satırlara otomatik uygular (özel `MigrationStage` gerekmez).
/// Kullanıcı verisi entity'leri değişmediğinden bu değişiklik onları BOZMAZ; cache
/// yeniden üretilebilir olduğundan eski satırların geçici `sizeBytes == 0` sayması da
/// zararsızdır (ilk `store` çağrısında gerçek `payload.count` ile tazelenir).
enum PersistenceSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            WatchProgressEntity.self,
            FavoriteEntity.self,
            CachedSeriesEntity.self,
            CachedEpisodeListEntity.self,
            FeedSnapshotEntity.self,
            CachedAssetRecordEntity.self
        ]
    }
}

/// Şema migration planı. V1'de (gün bir) stage yoktur; sonraki şema sürümleri buraya
/// `MigrationStage` olarak eklenir — yalnızca kullanıcı verisi entity'lerini taşıyacak
/// şekilde (05 §3.2).
enum PersistenceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistenceSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
