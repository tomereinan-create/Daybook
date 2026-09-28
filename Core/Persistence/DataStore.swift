import Foundation
import SwiftData

/// Builds the shared model container and bridges SwiftData to the engine.
///
/// Everything above this line is value types; everything below is storage.
@MainActor
final class DataStore {
    let container: ModelContainer
    /// True when the App Group container was unavailable and we fell back to a
    /// process-local store. The widgets will not see this data; Settings says so.
    let isUsingFallbackStore: Bool

    static let schema = Schema([Item.self, OccurrenceRecord.self])

    init(inMemory: Bool = false) {
        let (container, usedFallback) = Self.makeContainer(inMemory: inMemory)
        self.container = container
        self.isUsingFallbackStore = usedFallback
    }

    var context: ModelContext { container.mainContext }

    private static func makeContainer(inMemory: Bool) -> (ModelContainer, Bool) {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // A failure here means the schema itself is wrong, which is a
            // programmer error rather than a runtime condition.
            return (try! ModelContainer(for: schema, configurations: config), false)
        }

        if let url = AppGroup.storeURL {
            let config = ModelConfiguration(schema: schema, url: url)
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return (container, false)
            }
        }

        let local = ModelConfiguration(schema: schema)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return (container, true)
        }

        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return (try! ModelContainer(for: schema, configurations: memory), true)
    }

    // MARK: - Reading

    func allItems() -> [Item] {
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func snapshots() -> [ItemSnapshot] {
        allItems().map(\.snapshot)
    }

    func recordsByKey() -> [OccurrenceKey: OccurrenceStateRecord] {
        let descriptor = FetchDescriptor<OccurrenceRecord>()
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(rows.map { ($0.key, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    func item(with id: UUID) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Finds the record for an occurrence, creating it on first touch.
    func record(for key: OccurrenceKey) -> OccurrenceRecord {
        let itemID = key.itemID
        let slot = key.slot
        let descriptor = FetchDescriptor<OccurrenceRecord>(
            predicate: #Predicate { $0.itemID == itemID && $0.slot == slot }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = OccurrenceRecord(key: key)
        context.insert(created)
        return created
    }

    // MARK: - Writing

    func insert(_ item: Item) {
        context.insert(item)
        save()
    }

    func delete(_ item: Item) {
        let itemID = item.id
        let descriptor = FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.itemID == itemID })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        context.delete(item)
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Losing a write silently would be worse than a log: surface it.
            assertionFailure("DataStore save failed: \(error)")
        }
    }
}
