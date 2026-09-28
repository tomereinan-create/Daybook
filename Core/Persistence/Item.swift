import Foundation
import SwiftData

/// The stored form of an item.
///
/// The settings live as one JSON blob rather than as thirty separate SwiftData
/// attributes. That keeps the schema flat and migration-friendly, and costs us
/// nothing in practice because the engine always works on the whole settings
/// value anyway and the item count is small enough to filter in Swift.
@Model
final class Item {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var presetRaw: String = PresetKind.task.rawValue
    var settingsData: Data = Data()
    var isArchived: Bool = false
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        preset: PresetKind,
        settings: ItemSettings,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.presetRaw = preset.rawValue
        self.settingsData = Self.encode(settings)
        self.isArchived = false
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var preset: PresetKind {
        get { PresetKind(rawValue: presetRaw) ?? .task }
        set { presetRaw = newValue.rawValue }
    }

    var settings: ItemSettings {
        get {
            guard !settingsData.isEmpty,
                  let decoded = try? JSONDecoder().decode(ItemSettings.self, from: settingsData)
            else { return .default }
            return decoded
        }
        set { settingsData = Self.encode(newValue) }
    }

    var snapshot: ItemSnapshot {
        ItemSnapshot(
            id: id,
            title: title,
            notes: notes,
            preset: preset,
            settings: settings,
            isArchived: isArchived,
            createdAt: createdAt
        )
    }

    private static func encode(_ settings: ItemSettings) -> Data {
        (try? JSONEncoder().encode(settings)) ?? Data()
    }
}
