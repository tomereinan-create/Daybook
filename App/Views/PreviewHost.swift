import SwiftData
import SwiftUI

/// Wraps a preview in an in-memory store seeded with a handful of items, so
/// every canvas shows something real rather than an empty list.
struct PreviewHost<Content: View>: View {
    private let model: AppModel
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        let store = DataStore(inMemory: true)
        let model = AppModel(store: store)
        PreviewHost.seed(model)
        self.model = model
        self.content = content()
    }

    var body: some View {
        content
            .environment(model)
            .modelContainer(model.store.container)
    }

    @MainActor
    private static func seed(_ model: AppModel) {
        let calendar = Calendar.current
        let now = Date.now

        var standup = PresetKind.event.defaultSettings(reference: now, calendar: calendar)
        standup.trigger = .at(calendar.date(byAdding: .hour, value: 2, to: now) ?? now)
        model.createItem(title: "Team stand-up", notes: "", preset: .event, settings: standup, now: now)

        let errand = PresetKind.task.defaultSettings(reference: now, calendar: calendar)
        model.createItem(title: "Renew passport", notes: "", preset: .task, settings: errand, now: now)

        var teeth = PresetKind.recurringTask.defaultSettings(reference: now, calendar: calendar)
        teeth.trigger = .daily(at: calendar.timeOfDay(of: now))
        model.createItem(title: "Brush teeth", notes: "", preset: .recurringTask, settings: teeth, now: now)

        let gym = PresetKind.flexibleHabit.defaultSettings(reference: now, calendar: calendar)
        model.createItem(title: "Gym", notes: "", preset: .flexibleHabit, settings: gym, now: now)

        let laundry = PresetKind.relativeTimer.defaultSettings(reference: now, calendar: calendar)
        model.createItem(title: "Move the laundry", notes: "", preset: .relativeTimer, settings: laundry, now: now)
    }
}
