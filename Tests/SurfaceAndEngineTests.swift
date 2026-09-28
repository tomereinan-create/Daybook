import Foundation
import Testing
@testable import Daybook

@Suite("What each surface shows")
struct SurfacePlannerTests {
    let calendar = Fixture.calendar()

    private var now: Date { Fixture.date(2026, 3, 10, 9, 30, calendar: calendar) }
    private var anchor: Date { Fixture.date(2026, 3, 1, 0, 0, calendar: calendar) }

    /// A one-off item at a time on 10 March, so ordering tests are not also
    /// testing recurrence.
    private func item(
        _ title: String,
        at time: TimeOfDay,
        surfaces: SurfaceSet = .all,
        priority: Priority = .normal,
        leadTime: TimeInterval = 4 * 3600
    ) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.trigger = .at(Fixture.date(2026, 3, 10, time.hour, time.minute, calendar: calendar))
        settings.visibility = Visibility(leadTime: leadTime, surfaces: surfaces)
        settings.priority = priority
        return Fixture.item(title: title, settings: settings, createdAt: anchor)
    }

    private var engine: ScheduleEngine {
        ScheduleEngine(calendar: calendar, configuration: .default, quietHours: .default)
    }

    @Test("Overdue sorts above due, which sorts above merely visible")
    func urgencyDrivesTheOrder() {
        let overdue = item("Overdue", at: TimeOfDay(hour: 8, minute: 0))
        let due = item("Due", at: TimeOfDay(hour: 9, minute: 25))
        let later = item("Later", at: TimeOfDay(hour: 12, minute: 0))

        let entries = engine.entries(
            for: .homeWidget,
            items: [later, due, overdue],
            records: [:],
            now: now
        )
        #expect(entries.map(\.title) == ["Overdue", "Due", "Later"])
    }

    @Test("A recurring item is outstanding once, not once per day it was skipped")
    func yesterdaysCopiesAreSuperseded() {
        // Stays until done, and forgiving about being missed: without the
        // supersede rule this would pile up ten copies on the widget.
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 8, minute: 0))
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
        settings.visibility = Visibility(leadTime: 3600, surfaces: .all)
        settings.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)
        let item = Fixture.item(title: "Brush teeth", settings: settings, createdAt: anchor)

        let entries = engine.entries(for: .homeWidget, items: [item], records: [:], now: now)
        #expect(entries.count == 1)
        #expect(entries.first?.effectiveTrigger == Fixture.date(2026, 3, 10, 8, 0, calendar: calendar))

        // A one-off with the same policy really does wait forever.
        var oneOff = ItemSettings.default
        oneOff.trigger = .at(Fixture.date(2026, 3, 2, 8, 0, calendar: calendar))
        oneOff.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)
        let lingering = Fixture.item(title: "Passport", settings: oneOff, createdAt: anchor)
        #expect(engine.entries(for: .homeWidget, items: [lingering], records: [:], now: now).count == 1)
    }

    @Test("A mandatory item outranks everything, however far off it is")
    func mandatoryComesFirst() {
        let overdue = item("Overdue", at: TimeOfDay(hour: 8, minute: 0))
        let mandatory = item("Mandatory", at: TimeOfDay(hour: 12, minute: 0), priority: .mandatory)

        let entries = engine.entries(
            for: .homeWidget,
            items: [overdue, mandatory],
            records: [:],
            now: now
        )
        #expect(entries.first?.title == "Mandatory")
    }

    @Test("An app-only item never reaches the lock screen or the widget")
    func appOnlyStaysInTheApp() {
        let hidden = item("Hidden", at: TimeOfDay(hour: 9, minute: 25), surfaces: .appOnly)
        let shown = item("Shown", at: TimeOfDay(hour: 9, minute: 25))

        let widget = engine.entries(for: .homeWidget, items: [hidden, shown], records: [:], now: now)
        let lockScreen = engine.entries(for: .liveActivity, items: [hidden, shown], records: [:], now: now)
        let app = engine.entries(for: .app, items: [hidden, shown], records: [:], now: now)

        #expect(widget.map(\.title) == ["Shown"])
        #expect(lockScreen.map(\.title) == ["Shown"])
        #expect(app.contains { $0.title == "Hidden" })
    }

    @Test("Each surface is capped so a long day cannot overflow the card")
    func surfaceEntryCountsAreCapped() {
        let items = (0..<30).map { index in
            item("Item \(index)", at: TimeOfDay(hour: 9, minute: 25), leadTime: 8 * 3600)
        }
        let liveActivity = engine.entries(for: .liveActivity, items: items, records: [:], now: now)
        let widget = engine.entries(for: .homeWidget, items: items, records: [:], now: now)

        #expect(liveActivity.count == EngineConfiguration.default.liveActivityEntryCount)
        #expect(widget.count == EngineConfiguration.default.homeWidgetEntryCount)
    }

    @Test("Completed and upcoming items stay off the live surfaces")
    func liveSurfacesShowOnlyWhatIsLive() {
        let done = item("Done", at: TimeOfDay(hour: 9, minute: 0))
        let farOff = item("Far off", at: TimeOfDay(hour: 23, minute: 0), leadTime: 900)
        let records = Fixture.records([
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: done.id, slot: Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)),
                completedAt: now
            )
        ])

        let widget = engine.entries(for: .homeWidget, items: [done, farOff], records: records, now: now)
        #expect(widget.isEmpty)
    }
}

@Suite("The day the Today screen sees")
struct ScheduleEngineTests {
    let calendar = Fixture.calendar()

    private var now: Date { Fixture.date(2026, 3, 10, 9, 30, calendar: calendar) }
    private var anchor: Date { Fixture.date(2026, 3, 1, 0, 0, calendar: calendar) }

    private var engine: ScheduleEngine {
        ScheduleEngine(calendar: calendar, configuration: .default, quietHours: .default)
    }

    @Test("Yesterday's unfinished open task is carried into today")
    func openTasksCarryOver() {
        var settings = ItemSettings.default
        settings.trigger = .at(Fixture.date(2026, 3, 9, 10, 0, calendar: calendar))
        settings.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)
        let item = Fixture.item(title: "Yesterday", settings: settings, createdAt: anchor)

        let plan = engine.dayPlan(items: [item], records: [:], on: now, now: now)
        #expect(plan[.now].map(\.title) == ["Yesterday"])
        #expect(plan.outstandingCount == 1)
    }

    @Test("A missed one-off from yesterday does not follow the user around")
    func missedItemsDoNotCarryOver() {
        var settings = ItemSettings.default
        settings.trigger = .at(Fixture.date(2026, 3, 9, 10, 0, calendar: calendar))
        settings.dismissal = Dismissal(endCondition: .windowEnds(3600), onMissed: .logMissed)
        let item = Fixture.item(title: "Gone", settings: settings, createdAt: anchor)

        let plan = engine.dayPlan(items: [item], records: [:], on: now, now: now)
        #expect(plan[.now].isEmpty)
        #expect(plan[.missed].isEmpty)  // it belongs to yesterday, not today
    }

    @Test("Undated tasks land in Anytime, dated ones in Now or Later")
    func sectionsSplitTheDay() {
        let task = Fixture.item(title: "Passport", settings: .default, createdAt: anchor)

        var eventSettings = ItemSettings.default
        eventSettings.trigger = .at(Fixture.date(2026, 3, 10, 18, 0, calendar: calendar))
        eventSettings.visibility = Visibility(leadTime: 900, surfaces: .all)
        let later = Fixture.item(title: "Dinner", settings: eventSettings, createdAt: anchor)

        var dueSettings = ItemSettings.default
        dueSettings.trigger = .at(Fixture.date(2026, 3, 10, 9, 25, calendar: calendar))
        let due = Fixture.item(title: "Call back", settings: dueSettings, createdAt: anchor)

        let plan = engine.dayPlan(items: [task, later, due], records: [:], on: now, now: now)
        #expect(plan[.undated].map(\.title) == ["Passport"])
        #expect(plan[.upcoming].map(\.title) == ["Dinner"])
        #expect(plan[.now].map(\.title) == ["Call back"])
    }

    @Test("Someday and waiting-for stay out of today, but a plain task does not")
    func outOfSightItemsAreNotInTheDayPlan() {
        let someday = Fixture.item(
            title: "Learn to sail",
            preset: .someday,
            settings: PresetKind.someday.defaultSettings(reference: now, calendar: calendar),
            createdAt: anchor
        )
        let waiting = Fixture.item(
            title: "Hear back from the bank",
            preset: .waitingFor,
            settings: PresetKind.waitingFor.defaultSettings(reference: now, calendar: calendar),
            createdAt: anchor
        )
        let task = Fixture.item(
            title: "Passport",
            preset: .task,
            settings: PresetKind.task.defaultSettings(reference: now, calendar: calendar),
            createdAt: anchor
        )

        let plan = engine.dayPlan(items: [someday, waiting, task], records: [:], on: now, now: now)
        #expect(plan[.undated].map(\.title) == ["Passport"])
        #expect(plan.outstandingCount == 1)

        // They are still items, and the app still lists them.
        let inApp = engine.entries(for: .app, items: [someday, waiting, task], records: [:], now: now)
        #expect(inApp.count == 3)
    }

    @Test("A completed occurrence moves to the Done section")
    func doneMovesSection() {
        var settings = ItemSettings.default
        settings.trigger = .at(Fixture.date(2026, 3, 10, 9, 0, calendar: calendar))
        let item = Fixture.item(title: "Stand-up", settings: settings, createdAt: anchor)
        let records = Fixture.records([
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: item.id, slot: Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)),
                completedAt: Fixture.date(2026, 3, 10, 9, 5, calendar: calendar)
            )
        ])

        let plan = engine.dayPlan(items: [item], records: records, on: now, now: now)
        #expect(plan[.done].map(\.title) == ["Stand-up"])
        #expect(plan.completionCount == 1)
    }

    @Test("Quota progress reaches the surface as a counter")
    func quotaProgressIsCarried() {
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 3, period: .week),
            end: .never,
            anchorDate: anchor
        )
        settings.visibility = Visibility(leadTime: 0, surfaces: .all)
        let item = Fixture.item(title: "Gym", preset: .flexibleHabit, settings: settings, createdAt: anchor)

        let weekStart = calendar.startOfPeriod(.week, containing: now)
        let records = Fixture.records([
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: weekStart)),
                completionCount: 1
            )
        ])

        let entries = engine.entries(for: .homeWidget, items: [item], records: records, now: now)
        let gym = entries.first { $0.title == "Gym" }
        #expect(gym?.quotaProgress?.completed == 1)
        #expect(gym?.quotaProgress?.target == 3)
    }

    @Test("Location monitoring reports the overflow rather than dropping it silently")
    func locationCapIsSurfaced() {
        let items = (0..<25).map { index -> ItemSnapshot in
            var settings = ItemSettings.default
            settings.trigger = Trigger(
                kind: .location,
                location: LocationTrigger(
                    name: "Place \(index)",
                    latitude: 32.0 + Double(index) / 100,
                    longitude: 34.8,
                    radius: 100,
                    edge: .arrive
                )
            )
            return Fixture.item(title: "Place \(index)", settings: settings, createdAt: anchor)
        }

        let plan = engine.locationMonitoringPlan(items: items, records: [:], now: now)
        #expect(plan.monitored.count == EngineConfiguration.default.locationRegionLimit)
        #expect(plan.exceedsLimit)
        #expect(plan.overflow.count == 5)
    }
}

@Suite("Presets are only defaults")
struct PresetTests {
    let calendar = Fixture.calendar()
    private var now: Date { Fixture.date(2026, 3, 10, 9, 30, calendar: calendar) }

    @Test("Every preset round-trips through the stored JSON form unchanged", arguments: PresetKind.allCases)
    func settingsRoundTrip(preset: PresetKind) throws {
        let settings = preset.defaultSettings(reference: now, calendar: calendar)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ItemSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("Every preset produces an item the engine can place somewhere", arguments: PresetKind.allCases)
    func everyPresetResolves(preset: PresetKind) {
        let settings = preset.defaultSettings(reference: now, calendar: calendar)
        let item = Fixture.item(title: preset.rawValue, preset: preset, settings: settings, createdAt: now)
        let engine = ScheduleEngine(calendar: calendar, configuration: .default, quietHours: .default)

        let resolved = engine.live(items: [item], records: [:], now: now)
        // A location reminder has nowhere to fire until a place is chosen, but
        // it still exists as an open item.
        #expect(!resolved.isEmpty)
    }

    @Test("Someday and waiting-for never reach a surface on their own")
    func hiddenPresetsStayHidden() {
        let engine = ScheduleEngine(calendar: calendar, configuration: .default, quietHours: .default)
        for preset in [PresetKind.someday, .waitingFor] {
            let settings = preset.defaultSettings(reference: now, calendar: calendar)
            let item = Fixture.item(title: preset.rawValue, preset: preset, settings: settings, createdAt: now)
            #expect(engine.entries(for: .homeWidget, items: [item], records: [:], now: now).isEmpty)
            #expect(engine.entries(for: .liveActivity, items: [item], records: [:], now: now).isEmpty)
            #expect(!engine.entries(for: .app, items: [item], records: [:], now: now).isEmpty)
        }
    }

    @Test("The wake-up preset is the only default that asks for a real alarm")
    func onlyWakeUpUsesAlarmKit() {
        for preset in PresetKind.allCases {
            let settings = preset.defaultSettings(reference: now, calendar: calendar)
            if preset == .wakeUp {
                #expect(settings.alerting.intensity == .alarm)
                #expect(settings.quietHours == .override)
            } else {
                #expect(settings.alerting.intensity != .alarm)
            }
        }
    }

    @Test("A task carries no trigger and no alerts")
    func taskIsSilentAndUndated() {
        let settings = PresetKind.task.defaultSettings(reference: now, calendar: calendar)
        #expect(settings.trigger.kind == .none)
        #expect(settings.alerting.intensity == .none)
        #expect(settings.dismissal.endCondition == .markedDone)
    }
}
