import Foundation
import SwiftData

/// `FavoritesRepository`'nin SwiftData somut uygulaması (03 §9, 05 §3.3 optimistic toggle +
/// çevrimdışı kuyruk). `@ModelActor` ile arka plan context'ine hapsedilmiştir (03 §7.3).
/// Feature modülleri yalnız `FavoritesRepository` protokolünü görür.
@ModelActor
actor FavoritesStore: FavoritesRepository {
    func isFavorite(_ seriesID: SeriesID) throws -> Bool {
        try fetchEntity(seriesId: seriesID.rawValue).map { $0.syncState != FavoriteSyncState.pendingRemove.rawValue } ?? false
    }

    func favorites() throws -> [FavoriteRecord] {
        let removed = FavoriteSyncState.pendingRemove.rawValue
        let descriptor = FetchDescriptor<FavoriteEntity>(
            predicate: #Predicate { $0.syncState != removed },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(Self.record)
    }

    func addFavorite(_ seriesID: SeriesID, at date: Date) throws {
        if let existing = try fetchEntity(seriesId: seriesID.rawValue) {
            // Zaten favori (synced/pendingAdd) ise no-op; pendingRemove ise pendingAdd'e döner.
            if existing.syncState == FavoriteSyncState.pendingRemove.rawValue {
                existing.syncState = FavoriteSyncState.pendingAdd.rawValue
                existing.addedAt = date
                try modelContext.save()
            }
            return
        }
        modelContext.insert(FavoriteEntity(
            seriesId: seriesID.rawValue,
            addedAt: date,
            syncState: FavoriteSyncState.pendingAdd.rawValue
        ))
        try modelContext.save()
    }

    func removeFavorite(_ seriesID: SeriesID) throws {
        guard let existing = try fetchEntity(seriesId: seriesID.rawValue) else { return }
        // Hiç senkronlanmamış (pendingAdd) kayıt doğrudan silinir; aksi halde pendingRemove.
        if existing.syncState == FavoriteSyncState.pendingAdd.rawValue {
            modelContext.delete(existing)
        } else {
            existing.syncState = FavoriteSyncState.pendingRemove.rawValue
        }
        try modelContext.save()
    }

    func toggleFavorite(_ seriesID: SeriesID, at date: Date) throws -> Bool {
        // Aktör-izole, askı noktası olmayan tek adım: oku→değiştir→yaz atomiktir. Alt
        // yardımcılar (`isFavorite`/`addFavorite`/`removeFavorite`) senkron çalışır; bu metot
        // içinde `await` yoktur, dolayısıyla eşzamanlı iki toggle araya giremez (TOCTOU yok).
        let next = try !isFavorite(seriesID)
        if next {
            try addFavorite(seriesID, at: date)
        } else {
            try removeFavorite(seriesID)
        }
        return next
    }

    func pendingSync() throws -> [PendingFavoriteSync] {
        let synced = FavoriteSyncState.synced.rawValue
        let descriptor = FetchDescriptor<FavoriteEntity>(
            predicate: #Predicate { $0.syncState != synced },
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).compactMap { entity in
            FavoriteSyncState(rawValue: entity.syncState).map {
                PendingFavoriteSync(seriesID: SeriesID(entity.seriesId), state: $0)
            }
        }
    }

    func confirmAdd(_ seriesID: SeriesID) throws {
        guard let existing = try fetchEntity(seriesId: seriesID.rawValue),
              existing.syncState == FavoriteSyncState.pendingAdd.rawValue else { return }
        existing.syncState = FavoriteSyncState.synced.rawValue
        try modelContext.save()
    }

    func confirmRemoval(_ seriesID: SeriesID) throws {
        guard let existing = try fetchEntity(seriesId: seriesID.rawValue),
              existing.syncState == FavoriteSyncState.pendingRemove.rawValue else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    // MARK: - Yardımcılar

    private func fetchEntity(seriesId: String) throws -> FavoriteEntity? {
        var descriptor = FetchDescriptor<FavoriteEntity>(
            predicate: #Predicate { $0.seriesId == seriesId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func record(from entity: FavoriteEntity) -> FavoriteRecord {
        FavoriteRecord(seriesID: SeriesID(entity.seriesId), addedAt: entity.addedAt)
    }
}
