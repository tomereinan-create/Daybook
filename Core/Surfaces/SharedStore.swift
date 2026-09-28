import Foundation

/// One store per process, opened lazily.
///
/// The app and the widget extension are separate processes reading the same
/// App Group container. Each needs its own handle, and opening a
/// `ModelContainer` is expensive enough that a widget refresh should not pay
/// for it twice in one timeline.
@MainActor
enum SharedStore {
    private static var cached: DataStore?

    static var current: DataStore {
        if let cached { return cached }
        let store = DataStore()
        cached = store
        return store
    }

    /// Tests and previews hand in their own.
    static func override(_ store: DataStore) {
        cached = store
    }
}

/// What the widget and the Live Activity ask for, in one place, so both read
/// the day the same way the app does.
@MainActor
enum SurfaceData {
    static func engine() -> ScheduleEngine {
        ScheduleEngine(
            calendar: .current,
            configuration: .default,
            quietHours: SharedDefaults.quietHours
        )
    }

    static func entries(for surface: Surface, now: Date = .now) -> [ResolvedOccurrence] {
        let store = SharedStore.current
        return engine().entries(
            for: surface,
            items: store.snapshots(),
            records: store.recordsByKey(),
            now: now
        )
    }

    static func dayPlan(now: Date = .now) -> DayPlan {
        let store = SharedStore.current
        return engine().dayPlan(
            items: store.snapshots(),
            records: store.recordsByKey(),
            on: now,
            now: now
        )
    }

    /// How much of today is behind you. Drives the accessory circular widget.
    static func progress(now: Date = .now) -> (done: Int, total: Int) {
        let plan = dayPlan(now: now)
        let done = plan[.done].count
        let outstanding = plan.outstandingCount
        return (done, done + outstanding)
    }
}

/// Completing and snoozing from a surface that is not the app.
///
/// The widget button and the Live Activity button both land here. It is the
/// same `CompletionService` the UI uses — there is deliberately no second
/// implementation of what "done" means.
@MainActor
enum OccurrenceActions {
    private static let completion = CompletionService()

    @discardableResult
    static func complete(_ key: OccurrenceKey, now: Date = .now) -> CompletionOutcome? {
        let store = SharedStore.current
        guard let item = store.item(with: key.itemID) else { return nil }
        let row = store.record(for: key)
        let (updated, outcome) = completion.complete(row.state, item: item.snapshot, now: now)
        row.state = updated
        store.save()
        return outcome
    }

    @discardableResult
    static func snooze(_ key: OccurrenceKey, now: Date = .now) -> Bool {
        let store = SharedStore.current
        guard let item = store.item(with: key.itemID) else { return false }
        let row = store.record(for: key)
        guard let updated = completion.snooze(row.state, item: item.snapshot, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        return true
    }

    @discardableResult
    static func start(_ key: OccurrenceKey, now: Date = .now) -> Bool {
        let store = SharedStore.current
        guard let item = store.item(with: key.itemID) else { return false }
        let row = store.record(for: key)
        guard let updated = completion.start(row.state, item: item.snapshot, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        return true
    }
}
