import Foundation
import Testing
@testable import Daybook

// MARK: - Fakes

/// A notification centre that remembers what it was told, so the rolling
/// window can be tested without iOS.
actor FakeNotificationScheduler: NotificationScheduling {
    private(set) var pending: Set<String> = []
    private(set) var contents: [String: NotificationContent] = [:]
    private(set) var removedDelivered: [String] = []
    private(set) var categoriesRegistered = false
    private(set) var authorizationRequests = 0
    private var authorization: NotificationAuthorization

    init(authorization: NotificationAuthorization = .authorized, pending: Set<String> = []) {
        self.authorization = authorization
        self.pending = pending
    }

    func seed(_ identifiers: Set<String>) { pending = identifiers }

    func pendingIdentifiers() async -> Set<String> { pending }

    func add(_ notification: PlannedNotification, content: NotificationContent) async throws {
        pending.insert(notification.id)
        contents[notification.id] = content
    }

    func removePending(identifiers: [String]) async {
        pending.subtract(identifiers)
    }

    func removeDelivered(identifiers: [String]) async {
        removedDelivered.append(contentsOf: identifiers)
    }

    func authorizationStatus() async -> NotificationAuthorization { authorization }

    func requestAuthorization() async -> NotificationAuthorization {
        authorizationRequests += 1
        if authorization == .notDetermined { authorization = .authorized }
        return authorization
    }

    func registerCategories() async { categoriesRegistered = true }

    private(set) var testsSent = 0
    func sendTest() async throws { testsSent += 1 }

    private(set) var summary: DaySummary?
    private(set) var summaryPosts = 0
    func postSummary(_ summary: DaySummary?) async {
        self.summary = summary
        summaryPosts += 1
    }
}

actor FakeAlarmScheduler: AlarmScheduling {
    private(set) var scheduled: [UUID: PlannedAlarm] = [:]
    private(set) var cancelled: [UUID] = []
    private var authorization: AlarmAuthorization

    init(authorization: AlarmAuthorization = .authorized) {
        self.authorization = authorization
    }

    func scheduledIdentifiers() async -> Set<UUID> { Set(scheduled.keys) }

    func schedule(_ alarm: PlannedAlarm) async throws { scheduled[alarm.alarmID] = alarm }

    func cancel(ids: [UUID]) async {
        cancelled.append(contentsOf: ids)
        for id in ids { scheduled[id] = nil }
    }

    func authorizationStatus() async -> AlarmAuthorization { authorization }

    func requestAuthorization() async -> AlarmAuthorization {
        if authorization == .notDetermined { authorization = .authorized }
        return authorization
    }
}

// MARK: - Reconciler

@Suite("Reconciling the rolling window")
struct NotificationReconcilerTests {
    let calendar = Fixture.calendar()
    let reconciler = NotificationReconciler()

    private func planned(_ id: String, at fire: Date) -> PlannedNotification {
        PlannedNotification(
            id: id,
            key: OccurrenceKey(itemID: UUID(), slot: fire),
            title: "Thing",
            fireDate: fire,
            intensity: .standard,
            role: .primary,
            sequence: 0,
            isMandatory: false,
            snoozeMinutes: nil,
            triggerDate: fire
        )
    }

    @Test("Nothing pending means everything is added")
    func addsEverythingWhenEmpty() {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let plan = [planned("a", at: now), planned("b", at: now.addingTimeInterval(600))]

        let work = reconciler.reconcile(plan: plan, pending: [])
        #expect(work.toAdd.map(\.id) == ["a", "b"])
        #expect(work.toRemove.isEmpty)
        #expect(work.unchanged.isEmpty)
    }

    @Test("A second pass over an unchanged plan does nothing at all")
    func isIdempotent() {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let plan = [planned("a", at: now), planned("b", at: now.addingTimeInterval(600))]

        let work = reconciler.reconcile(plan: plan, pending: ["a", "b"])
        #expect(work.isEmpty)
        #expect(work.unchanged == ["a", "b"])
    }

    @Test("Pending requests that fell out of the plan are cancelled")
    func removesExpired() {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let work = reconciler.reconcile(plan: [planned("b", at: now)], pending: ["a", "b", "c"])
        #expect(work.toRemove == ["a", "c"])
        #expect(work.unchanged == ["b"])
        #expect(work.toAdd.isEmpty)
    }

    @Test("An alert whose time moved is replaced, not left stale")
    func replacesMovedAlerts() {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let key = OccurrenceKey(itemID: UUID(), slot: now)
        let oldID = NotificationPlanner.identifier(key, role: .primary, sequence: 0, fireDate: now)
        let moved = now.addingTimeInterval(1800)
        let newID = NotificationPlanner.identifier(key, role: .primary, sequence: 0, fireDate: moved)

        #expect(oldID != newID)
        let work = reconciler.reconcile(plan: [planned(newID, at: moved)], pending: [oldID])
        #expect(work.toRemove == [oldID])
        #expect(work.toAdd.map(\.id) == [newID])
    }

    @Test("One occurrence's whole family of alerts can be found by prefix")
    func findsAFamilyByPrefix() {
        let itemID = UUID()
        let slot = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let mine = OccurrenceKey(itemID: itemID, slot: slot)
        let tomorrow = OccurrenceKey(itemID: itemID, slot: slot.addingTimeInterval(86_400))
        let other = OccurrenceKey(itemID: UUID(), slot: slot)

        let pending: Set<String> = [
            NotificationPlanner.identifier(mine, role: .primary, sequence: 0, fireDate: slot),
            NotificationPlanner.identifier(mine, role: .nag, sequence: 0, fireDate: slot),
            NotificationPlanner.identifier(mine, role: .nag, sequence: 1, fireDate: slot),
            NotificationPlanner.identifier(tomorrow, role: .primary, sequence: 0, fireDate: slot),
            NotificationPlanner.identifier(other, role: .primary, sequence: 0, fireDate: slot)
        ]

        // One occurrence: today's three, not tomorrow's and not the other item's.
        #expect(reconciler.identifiers(in: pending, for: mine).count == 3)
        // The whole item: today's three plus tomorrow's one.
        #expect(reconciler.identifiers(in: pending, forItem: itemID).count == 4)
    }
}

// MARK: - Coordinator

@Suite("Scheduling end to end")
struct ScheduleCoordinatorTests {
    let calendar = Fixture.calendar()

    private var now: Date { Fixture.date(2026, 3, 10, 8, 0, calendar: calendar) }
    private var anchor: Date { Fixture.date(2026, 3, 1, 0, 0, calendar: calendar) }

    private func engine(quietHours: QuietHours = QuietHours(isEnabled: false, start: TimeOfDay(hour: 0, minute: 0), end: TimeOfDay(hour: 0, minute: 0))) -> ScheduleEngine {
        ScheduleEngine(calendar: calendar, configuration: .default, quietHours: quietHours)
    }

    private func pillsItem(intensity: Intensity = .standard, nag: Nag = .off) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 20, minute: 0))
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
        settings.alerting = Alerting(
            intensity: intensity,
            preAlertOffsets: [],
            nag: nag,
            escalates: false,
            snoozeAllowed: true,
            snoozeMinutes: 10
        )
        return Fixture.item(title: "Pills", preset: .recurringTask, settings: settings, createdAt: anchor)
    }

    @Test("A first run registers the plan; a second changes nothing")
    func firstRunSchedulesAndSecondIsQuiet() async {
        let item = pillsItem(nag: .every(10, upTo: 2))
        let notifications = FakeNotificationScheduler()
        let alarms = FakeAlarmScheduler()
        let coordinator = ScheduleCoordinator(engine: engine(), notifications: notifications, alarms: alarms)

        let first = await coordinator.refresh(items: [item], records: [:], now: now)
        #expect(first.added > 0)
        #expect(first.removed == 0)

        let second = await coordinator.refresh(items: [item], records: [:], now: now)
        #expect(second.added == 0)
        #expect(second.removed == 0)
        #expect(second.kept == first.added)
    }

    @Test("Completing an occurrence cancels its pending nags at once")
    func completionCancelsTheFamily() async {
        let item = pillsItem(nag: .every(10, upTo: 3))
        let notifications = FakeNotificationScheduler()
        let alarms = FakeAlarmScheduler()
        let coordinator = ScheduleCoordinator(engine: engine(), notifications: notifications, alarms: alarms)

        await coordinator.refresh(items: [item], records: [:], now: now)
        let slot = Fixture.date(2026, 3, 10, 20, 0, calendar: calendar)
        let key = OccurrenceKey(itemID: item.id, slot: slot)

        let before = await notifications.pendingIdentifiers()
        #expect(before.contains { $0.hasPrefix(NotificationPlanner.prefix(for: key)) })

        await coordinator.cancelAlerts(for: key)

        let after = await notifications.pendingIdentifiers()
        #expect(!after.contains { $0.hasPrefix(NotificationPlanner.prefix(for: key)) })
        // Tomorrow's are untouched.
        #expect(!after.isEmpty)
    }

    @Test("Nothing is scheduled when notifications are denied")
    func deniedPermissionSchedulesNothing() async {
        let item = pillsItem()
        let notifications = FakeNotificationScheduler(authorization: .denied)
        let alarms = FakeAlarmScheduler(authorization: .denied)
        let coordinator = ScheduleCoordinator(engine: engine(), notifications: notifications, alarms: alarms)

        let outcome = await coordinator.refresh(items: [item], records: [:], now: now)
        #expect(outcome.added == 0)
        #expect(outcome.notificationAuthorization == .denied)
        let pending = await notifications.pendingIdentifiers()
        #expect(pending.isEmpty)
    }

    @Test("A daily wake-up becomes one repeating alarm, not one per day")
    func wakeUpIsASingleRepeatingAlarm() async {
        var settings = PresetKind.wakeUp.defaultSettings(reference: anchor, calendar: calendar)
        settings.recurrence = Recurrence(
            frequency: .weekdays([.monday, .wednesday, .friday]),
            end: .never,
            anchorDate: anchor
        )
        let item = Fixture.item(title: "Wake up", preset: .wakeUp, settings: settings, createdAt: anchor)

        let notifications = FakeNotificationScheduler()
        let alarms = FakeAlarmScheduler()
        let coordinator = ScheduleCoordinator(engine: engine(), notifications: notifications, alarms: alarms)

        let outcome = await coordinator.refresh(items: [item], records: [:], now: now)
        #expect(outcome.alarmsScheduled == 1)

        let stored = await alarms.scheduled
        #expect(stored.count == 1)
        let alarm = stored.values.first
        #expect(alarm?.repeatsWeekly == true)
        #expect(alarm?.weekdays == [.monday, .wednesday, .friday])
        // A repeating alarm is identified by its item, so it is stable across days.
        #expect(alarm?.alarmID == item.id)
        // And it never touches the notification budget.
        let pending = await notifications.pendingIdentifiers()
        #expect(pending.isEmpty)
    }

    @Test("An alarm that is no longer wanted is cancelled")
    func staleAlarmsAreCancelled() async {
        var settings = PresetKind.wakeUp.defaultSettings(reference: anchor, calendar: calendar)
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
        let item = Fixture.item(title: "Wake up", preset: .wakeUp, settings: settings, createdAt: anchor)

        let notifications = FakeNotificationScheduler()
        let alarms = FakeAlarmScheduler()
        let coordinator = ScheduleCoordinator(engine: engine(), notifications: notifications, alarms: alarms)

        await coordinator.refresh(items: [item], records: [:], now: now)
        #expect(await alarms.scheduled.count == 1)

        // The item is gone; the alarm has to go with it.
        await coordinator.refresh(items: [], records: [:], now: now)
        #expect(await alarms.scheduled.isEmpty)
        #expect(await alarms.cancelled.count == 1)
    }

    @Test("A deterministic alarm id is stable and distinct per occurrence")
    func alarmIdentifiersAreDerived() {
        let itemID = UUID()
        let slot = Fixture.date(2026, 3, 10, 7, 0, calendar: calendar)
        let key = OccurrenceKey(itemID: itemID, slot: slot)
        let tomorrow = OccurrenceKey(itemID: itemID, slot: slot.addingTimeInterval(86_400))

        #expect(NotificationPlanner.alarmID(for: key) == NotificationPlanner.alarmID(for: key))
        #expect(NotificationPlanner.alarmID(for: key) != NotificationPlanner.alarmID(for: tomorrow))
    }

    @Test("Categories are registered before anything is scheduled")
    func preparesCategories() async {
        let notifications = FakeNotificationScheduler()
        let coordinator = ScheduleCoordinator(
            engine: engine(),
            notifications: notifications,
            alarms: FakeAlarmScheduler()
        )
        await coordinator.prepare()
        #expect(await notifications.categoriesRegistered)
    }
}

// MARK: - Content

@Suite("What a notification says")
struct NotificationContentTests {
    let calendar = Fixture.calendar()
    let builder = NotificationContentBuilder()

    private func notification(role: AlertRole, sequence: Int = 0, snooze: Int? = 10, lead: TimeInterval = 0) -> PlannedNotification {
        let fire = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        return PlannedNotification(
            id: "x",
            key: OccurrenceKey(itemID: UUID(), slot: fire),
            title: "Physio exercises",
            fireDate: fire,
            intensity: .standard,
            role: role,
            sequence: sequence,
            isMandatory: false,
            snoozeMinutes: snooze,
            triggerDate: fire.addingTimeInterval(lead)
        )
    }

    @Test("Intensity maps onto the system's interruption levels")
    func intensityMapsToLevels() {
        #expect(builder.level(for: .silent) == .passive)
        #expect(builder.level(for: .standard) == .active)
        #expect(builder.level(for: .timeSensitive) == .timeSensitive)
        #expect(builder.level(for: .alarm) == .timeSensitive)
    }

    @Test("Only a snoozable item gets the category with a snooze button")
    func categoryFollowsSnooze() {
        #expect(builder.category(for: notification(role: .primary, snooze: 10)) == .actionableWithSnooze)
        #expect(builder.category(for: notification(role: .primary, snooze: nil)) == .actionable)
    }

    @Test("The payload carries enough to find the occurrence again")
    func payloadRoundTrips() {
        let planned = notification(role: .primary)
        let content = builder.content(for: planned)
        let recovered = NotificationDelegate.occurrenceKey(from: content.userInfo)

        #expect(recovered?.itemID == planned.key.itemID)
        #expect(recovered.map { Int($0.slot.timeIntervalSince1970) } == Int(planned.key.slot.timeIntervalSince1970))
    }

    @Test("Every role produces a non-empty body")
    func everyRoleSpeaks() {
        for role in AlertRole.allCases {
            let text = builder.body(for: notification(role: role, lead: 3600))
            #expect(!text.isEmpty)
        }
    }
}

@Suite("The day held on the lock screen")
struct DaySummaryTests {
    let calendar = Fixture.calendar()
    let engine = ScheduleEngine(
        calendar: Fixture.calendar(),
        configuration: .default,
        quietHours: .default
    )
    private var now: Date { Fixture.date(2026, 3, 10, 9, 0, calendar: calendar) }

    private func plan(_ items: [ItemSnapshot], records: [OccurrenceKey: OccurrenceStateRecord] = [:]) -> DayPlan {
        engine.dayPlan(items: items, records: records, on: now, now: now)
    }

    private func task(_ title: String, at hour: Int? = nil) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.visibility = Visibility(leadTime: 24 * 3600, surfaces: .all)
        if let hour {
            settings.trigger = .at(Fixture.date(2026, 3, 10, hour, 0, calendar: calendar))
        }
        return Fixture.item(title: title, settings: settings, createdAt: now)
    }

    @Test("Nothing outstanding means nothing on the lock screen")
    func anEmptyDayTakesItDown() {
        #expect(DaySummaryBuilder().summary(for: plan([]), now: now) == nil)
    }

    @Test("It counts what is done and lists what is not")
    func itListsTheDay() {
        let items = [task("Weigh in"), task("Brush teeth", at: 8), task("Call the bank", at: 14)]
        let summary = DaySummaryBuilder().summary(for: plan(items), now: now)

        #expect(summary != nil)
        #expect(summary?.body.contains("Call the bank") == true)
        #expect(summary?.body.contains("Weigh in") == true)
        // Something to finish from the lock screen without opening the app.
        #expect(summary?.next != nil)
    }

    @Test("A long day is truncated honestly rather than silently")
    func itSaysHowManyItLeftOut() {
        let items = (1...10).map { task("Item \($0)") }
        var builder = DaySummaryBuilder()
        builder.maximumLines = 4
        let summary = builder.summary(for: plan(items), now: now)

        let lines = summary?.body.split(separator: "\n") ?? []
        // Four items and one line accounting for the rest.
        #expect(lines.count == 5)
        #expect(lines.last?.contains("6") == true)
    }

    @Test("Switched off, it takes down whatever is there")
    func disablingRemovesIt() async {
        let notifications = FakeNotificationScheduler()
        let coordinator = ScheduleCoordinator(
            engine: engine,
            notifications: notifications,
            alarms: FakeAlarmScheduler()
        )
        await coordinator.refreshDaySummary(
            plan: plan([task("Weigh in")]),
            enabled: false,
            now: now
        )
        #expect(await notifications.summaryPosts == 1)
        #expect(await notifications.summary == nil)
    }

    @Test("Without permission it is not posted at all")
    func noPermissionMeansNoSummary() async {
        let notifications = FakeNotificationScheduler(authorization: .denied)
        let coordinator = ScheduleCoordinator(
            engine: engine,
            notifications: notifications,
            alarms: FakeAlarmScheduler()
        )
        await coordinator.refreshDaySummary(
            plan: plan([task("Weigh in")]),
            enabled: true,
            now: now
        )
        #expect(await notifications.summary == nil)
    }

    @Test("Switched on, the day is posted")
    func enablingPostsIt() async {
        let notifications = FakeNotificationScheduler()
        let coordinator = ScheduleCoordinator(
            engine: engine,
            notifications: notifications,
            alarms: FakeAlarmScheduler()
        )
        await coordinator.refreshDaySummary(
            plan: plan([task("Weigh in"), task("Brush teeth", at: 8)]),
            enabled: true,
            now: now
        )
        let summary = await notifications.summary
        #expect(summary != nil)
        #expect(summary?.body.contains("Weigh in") == true)
    }
}
