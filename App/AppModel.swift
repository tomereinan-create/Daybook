import Foundation
import SwiftData
import SwiftUI

/// Owns the store and the engine, and is the only place a view calls to change
/// something. Views read; this writes.
@MainActor
@Observable
final class AppModel {
    let store: DataStore
    private(set) var engine: ScheduleEngine
    private let completion = CompletionService()

    /// Bumped whenever the store changes, so views recompute their plan.
    private(set) var revision: Int = 0

    init(store: DataStore) {
        self.store = store
        self.engine = ScheduleEngine(
            calendar: .current,
            configuration: .default,
            quietHours: SharedDefaults.quietHours
        )
    }

    // MARK: - Reading

    func dayPlan(for day: Date, now: Date) -> DayPlan {
        engine.dayPlan(
            items: store.snapshots(),
            records: store.recordsByKey(),
            on: day,
            now: now
        )
    }

    func allItems() -> [Item] { store.allItems() }

    /// Items that never appear on a surface and are reviewed instead.
    func items(matching preset: PresetKind) -> [Item] {
        store.allItems().filter { $0.preset == preset && !$0.isArchived }
    }

    // MARK: - Writing

    @discardableResult
    func complete(_ occurrence: ResolvedOccurrence, now: Date = .now) -> CompletionOutcome {
        let row = store.record(for: occurrence.key)
        let (updated, outcome) = completion.complete(row.state, item: occurrence.item, now: now)
        row.state = updated
        store.save()
        didChange()
        return outcome
    }

    func reopen(_ occurrence: ResolvedOccurrence) {
        let row = store.record(for: occurrence.key)
        row.state = completion.reopen(row.state, item: occurrence.item)
        store.save()
        didChange()
    }

    /// Returns false when the item does not allow snoozing, so the caller can
    /// avoid offering the action at all.
    @discardableResult
    func snooze(_ occurrence: ResolvedOccurrence, now: Date = .now) -> Bool {
        let row = store.record(for: occurrence.key)
        guard let updated = completion.snooze(row.state, item: occurrence.item, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        didChange()
        return true
    }

    @discardableResult
    func start(_ occurrence: ResolvedOccurrence, now: Date = .now) -> Bool {
        let row = store.record(for: occurrence.key)
        guard let updated = completion.start(row.state, item: occurrence.item, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        didChange()
        return true
    }

    func createItem(title: String, notes: String, preset: PresetKind, settings: ItemSettings, now: Date = .now) {
        let item = Item(
            title: title,
            notes: notes,
            preset: preset,
            settings: settings,
            createdAt: now
        )
        store.insert(item)
        didChange()
    }

    func update(_ item: Item, title: String, notes: String, settings: ItemSettings, now: Date = .now) {
        item.title = title
        item.notes = notes
        item.settings = settings
        item.updatedAt = now
        store.save()
        didChange()
    }

    func delete(_ item: Item) {
        store.delete(item)
        didChange()
    }

    func setArchived(_ item: Item, _ archived: Bool) {
        item.isArchived = archived
        store.save()
        didChange()
    }

    func updateQuietHours(_ quietHours: QuietHours) {
        SharedDefaults.quietHours = quietHours
        engine = ScheduleEngine(
            calendar: .current,
            configuration: engine.configuration,
            quietHours: quietHours
        )
        didChange()
    }

    /// Phase 2 hangs notification rescheduling off this; today it is the
    /// signal that makes the views recompute.
    private func didChange() {
        revision &+= 1
    }
}
