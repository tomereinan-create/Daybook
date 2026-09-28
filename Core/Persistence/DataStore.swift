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

        // Preferred: the App Group container, which the widgets and the Live
        // Activity intents can also open.
        if let url = AppGroup.storeURL, ensureDirectoryExists(url.deletingLastPathComponent()) {
            let config = ModelConfiguration(schema: schema, url: url)
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return (container, false)
            }
        }

        // Fallback: this process only. Reached when the App Groups entitlement
        // is missing — an unsigned simulator build, or a misconfigured app ID.
        // Application Support does not exist in a fresh container, and SwiftData
        // will not create it, so make it ourselves rather than lose the store.
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let url = support.appending(path: "Daybook.store")
            let config = ModelConfiguration(schema: schema, url: url)
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return (container, true)
            }
        }

        // Last resort. Data will not survive the process, so the app says so
        // rather than pretending everything is fine.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: memory) {
            return (container, true)
        }
        // A failure here means the schema itself is invalid, which the tests
        // would have caught long before a user ever ran this.
        preconditionFailure("Could not open a model container for the Daybook schema.")
    }

    @discardableResult
    private static func ensureDirectoryExists(_ url: URL) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path(percentEncoded: false)) { return true }
        do {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
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
