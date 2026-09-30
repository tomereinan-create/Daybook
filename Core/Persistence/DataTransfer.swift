import Foundation

/// A whole Daybook, as one JSON file.
///
/// This exists because the data lives nowhere else. There is no account and no
/// server, so a backup is the only thing standing between a reinstall and
/// losing everything — and a sideloaded build has to be reinstalled every
/// seven days.
nonisolated struct DataExport: Codable, Sendable {
    /// Bumped whenever the shape changes, so an old file can still be read.
    var version: Int = 1
    var exportedAt: Date
    var items: [ExportedItem]
    var records: [ExportedRecord]

    nonisolated struct ExportedItem: Codable, Sendable {
        var id: UUID
        var title: String
        var notes: String
        var preset: PresetKind
        var settings: ItemSettings
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    nonisolated struct ExportedRecord: Codable, Sendable {
        var itemID: UUID
        var slot: Date
        var completedAt: Date?
        var missedAt: Date?
        var snoozedUntil: Date?
        var startedAt: Date?
        var currentStepIndex: Int
        var nagsFired: Int
        var completionCount: Int
        /// Optional so a backup written by an earlier build still restores.
        var answer: String?
        var holdUntil: Date?
    }

    /// Readable on purpose. If Daybook ever disappears, this file should still
    /// make sense to a person opening it in a text editor.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    var summary: String {
        "\(items.count) items, \(records.count) records"
    }
}

nonisolated enum DataTransferError: Error, Sendable {
    case unreadable
    case unsupportedVersion(Int)
}

@MainActor
enum DataTransfer {
    // MARK: - Out

    static func export(from store: DataStore, now: Date = .now) throws -> Data {
        let items = store.allItems().map { item in
            DataExport.ExportedItem(
                id: item.id,
                title: item.title,
                notes: item.notes,
                preset: item.preset,
                settings: item.settings,
                isArchived: item.isArchived,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
        }
        let records = store.recordsByKey().values.map { state in
            DataExport.ExportedRecord(
                itemID: state.key.itemID,
                slot: state.key.slot,
                completedAt: state.completedAt,
                missedAt: state.missedAt,
                snoozedUntil: state.snoozedUntil,
                startedAt: state.startedAt,
                currentStepIndex: state.currentStepIndex,
                nagsFired: state.nagsFired,
                completionCount: state.completionCount,
                answer: state.answer,
                holdUntil: state.holdUntil
            )
        }
        let payload = DataExport(
            exportedAt: now,
            items: items,
            records: records.sorted { $0.slot < $1.slot }
        )
        return try DataExport.encoder().encode(payload)
    }

    /// Where the exported file is written before it is shared.
    static func writeExport(from store: DataStore, now: Date = .now) throws -> URL {
        let data = try export(from: store, now: now)
        let stamp = now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Daybook-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - In

    static func read(_ data: Data) throws -> DataExport {
        guard let payload = try? DataExport.decoder().decode(DataExport.self, from: data) else {
            throw DataTransferError.unreadable
        }
        guard payload.version == 1 else {
            throw DataTransferError.unsupportedVersion(payload.version)
        }
        return payload
    }

    /// Replaces everything with the contents of a file.
    ///
    /// Replace rather than merge, deliberately: merging two histories of the
    /// same item silently invents a third, and a restore should put the app
    /// back exactly as it was.
    @discardableResult
    static func restore(_ payload: DataExport, into store: DataStore) -> Int {
        for existing in store.allItems() {
            store.delete(existing)
        }

        for exported in payload.items {
            let item = Item(
                id: exported.id,
                title: exported.title,
                notes: exported.notes,
                preset: exported.preset,
                settings: exported.settings,
                createdAt: exported.createdAt
            )
            item.isArchived = exported.isArchived
            item.updatedAt = exported.updatedAt
            store.context.insert(item)
        }

        for exported in payload.records {
            let key = OccurrenceKey(itemID: exported.itemID, slot: exported.slot)
            let row = store.record(for: key)
            row.state = OccurrenceStateRecord(
                key: key,
                completedAt: exported.completedAt,
                missedAt: exported.missedAt,
                snoozedUntil: exported.snoozedUntil,
                startedAt: exported.startedAt,
                currentStepIndex: exported.currentStepIndex,
                nagsFired: exported.nagsFired,
                completionCount: exported.completionCount,
                answer: exported.answer,
                holdUntil: exported.holdUntil
            )
        }

        store.save()
        return payload.items.count
    }
}
