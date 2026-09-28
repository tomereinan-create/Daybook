import Foundation
import Testing
@testable import Daybook

@Suite("Notification planning and the 64-request cap")
struct NotificationPlannerTests {
    let calendar = Fixture.calendar()

    private var now: Date { Fixture.date(2026, 3, 10, 8, 0, calendar: calendar) }

    private func engine(
        budget: Int = EngineConfiguration.default.notificationBudget,
        quietHours: QuietHours = QuietHours(isEnabled: false, start: TimeOfDay(hour: 0, minute: 0), end: TimeOfDay(hour: 0, minute: 0))
    ) -> ScheduleEngine {
        var configuration = EngineConfiguration.default
        configuration.notificationBudget = budget
        return ScheduleEngine(calendar: calendar, configuration: configuration, quietHours: quietHours)
    }

    private func alertingItem(
        title: String,
        at time: TimeOfDay,
        intensity: Intensity = .standard,
        preAlerts: [TimeInterval] = [],
        nag: Nag = .off,
        escalates: Bool = false,
        priority: Priority = .normal,
        quietHours: QuietHoursPolicy = .respect
    ) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.trigger = .daily(at: time)
        settings.recurrence = Recurrence(
            frequency: .daily,
            end: .never,
            anchorDate: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        )
        settings.alerting = Alerting(
            intensity: intensity,
            preAlertOffsets: preAlerts,
            nag: nag,
            escalates: escalates,
            snoozeAllowed: true,
            snoozeMinutes: 10
        )
        settings.priority = priority
        settings.quietHours = quietHours
        settings.dismissal = Dismissal(endCondition: .markedDone, onMissed: .logMissed)
        return Fixture.item(title: title, preset: .recurringTask, settings: settings, createdAt: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar))
    }

    @Test("A plain item produces one notification at its trigger")
    func singlePrimaryAlert() {
        let item = alertingItem(title: "Pills", at: TimeOfDay(hour: 20, minute: 0))
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)

        let primaries = plan.notifications.filter { $0.role == .primary }
        #expect(primaries.count == 2)  // today and tomorrow, inside a 48h window
        #expect(primaries.allSatisfy { $0.intensity == .standard })
    }

    @Test("Pre-alerts land before the trigger and nothing is scheduled in the past")
    func preAlertsAreScheduledAhead() {
        let item = alertingItem(
            title: "Dentist",
            at: TimeOfDay(hour: 15, minute: 0),
            preAlerts: [3600, 600]
        )
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        let today = plan.notifications.filter {
            calendar.isDate($0.fireDate, inSameDayAs: now)
        }
        #expect(today.contains { $0.role == .preAlert && $0.fireDate == Fixture.date(2026, 3, 10, 14, 0, calendar: calendar) })
        #expect(today.contains { $0.role == .preAlert && $0.fireDate == Fixture.date(2026, 3, 10, 14, 50, calendar: calendar) })
        #expect(plan.notifications.allSatisfy { $0.fireDate > now })
    }

    @Test("Nags repeat at their interval and stop at the maximum")
    func nagsRepeatAndStop() {
        let item = alertingItem(
            title: "Stretch",
            at: TimeOfDay(hour: 9, minute: 0),
            nag: .every(10, upTo: 3)
        )
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        let nags = plan.notifications
            .filter { $0.role == .nag && calendar.isDate($0.fireDate, inSameDayAs: now) }
            .sorted { $0.fireDate < $1.fireDate }

        #expect(nags.count == 3)
        #expect(nags.map(\.fireDate) == [
            Fixture.date(2026, 3, 10, 9, 10, calendar: calendar),
            Fixture.date(2026, 3, 10, 9, 20, calendar: calendar),
            Fixture.date(2026, 3, 10, 9, 30, calendar: calendar)
        ])
    }

    @Test("Escalation raises each nag a rung but never reaches alarm")
    func escalationClimbsButStopsShortOfAlarm() {
        let item = alertingItem(
            title: "Deadline",
            at: TimeOfDay(hour: 9, minute: 0),
            intensity: .standard,
            nag: .every(10, upTo: 4),
            escalates: true
        )
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        let nags = plan.notifications
            .filter { $0.role == .nag && calendar.isDate($0.fireDate, inSameDayAs: now) }
            .sorted { $0.fireDate < $1.fireDate }

        #expect(nags.map(\.intensity) == [.timeSensitive, .timeSensitive, .timeSensitive, .timeSensitive])
        #expect(nags.allSatisfy { $0.intensity != .alarm })
    }

    @Test("Nags stop when the occurrence's window closes")
    func nagsStopAtTheWindow() {
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 9, minute: 0))
        settings.recurrence = Recurrence(
            frequency: .daily,
            end: .never,
            anchorDate: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        )
        settings.alerting = Alerting(
            intensity: .standard,
            preAlertOffsets: [],
            nag: .every(10, upTo: 10),
            escalates: false,
            snoozeAllowed: false,
            snoozeMinutes: 10
        )
        settings.dismissal = Dismissal(endCondition: .windowEnds(25 * 60), onMissed: .logMissed)
        let item = Fixture.item(title: "Short window", settings: settings, createdAt: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar))

        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        let nags = plan.notifications.filter {
            $0.role == .nag && calendar.isDate($0.fireDate, inSameDayAs: now)
        }
        // 09:10 and 09:20 fit; 09:30 is past the 09:25 window end.
        #expect(nags.count == 2)
    }

    @Test("Quiet hours silence an item that respects them and not one that overrides")
    func quietHoursAreHonoured() {
        let quiet = QuietHours(
            isEnabled: true,
            start: TimeOfDay(hour: 22, minute: 0),
            end: TimeOfDay(hour: 7, minute: 0)
        )
        let respectful = alertingItem(title: "Respectful", at: TimeOfDay(hour: 23, minute: 0))
        let insistent = alertingItem(
            title: "Insistent",
            at: TimeOfDay(hour: 23, minute: 0),
            quietHours: .override
        )

        let plan = engine(quietHours: quiet).notificationPlan(
            items: [respectful, insistent],
            records: [:],
            now: now
        )
        #expect(!plan.notifications.contains { $0.title == "Respectful" })
        #expect(plan.notifications.contains { $0.title == "Insistent" })
    }

    @Test("The plan never exceeds the budget, and spends it on primaries first")
    func budgetIsRespected() {
        // Thirty items, each wanting a primary plus eight nags: far more than
        // the cap allows.
        let items = (0..<30).map { index in
            alertingItem(
                title: "Item \(index)",
                at: TimeOfDay(hour: 9, minute: index),
                nag: .every(5, upTo: 8)
            )
        }
        let plan = engine(budget: 40).notificationPlan(items: items, records: [:], now: now)

        #expect(plan.notifications.count == 40)
        #expect(plan.droppedCount > 0)
        // Every one of today's primaries survived before a single nag got in.
        let primaries = plan.notifications.filter { $0.role == .primary }
        #expect(primaries.count == 40)
    }

    @Test("A mandatory item keeps its slot when the budget is tight")
    func mandatoryWinsTheBudget() {
        var items = (0..<20).map { index in
            alertingItem(title: "Normal \(index)", at: TimeOfDay(hour: 9, minute: index))
        }
        // Latest of all, so only priority can save it.
        items.append(
            alertingItem(title: "Critical", at: TimeOfDay(hour: 23, minute: 30), priority: .mandatory)
        )

        let plan = engine(budget: 3).notificationPlan(items: items, records: [:], now: now)
        #expect(plan.notifications.count == 3)
        #expect(plan.notifications.contains { $0.title == "Critical" })
    }

    @Test("Alarm intensity goes to AlarmKit, not to the notification budget")
    func alarmsAreRoutedSeparately() {
        let alarm = alertingItem(title: "Wake up", at: TimeOfDay(hour: 7, minute: 0), intensity: .alarm)
        let plan = engine().notificationPlan(items: [alarm], records: [:], now: now)

        #expect(plan.notifications.isEmpty)
        #expect(!plan.alarms.isEmpty)
        #expect(plan.alarms.allSatisfy { $0.title == "Wake up" })
    }

    @Test("A display-only item is never scheduled at all")
    func displayOnlyItemsAreSilent() {
        let item = alertingItem(title: "Quiet", at: TimeOfDay(hour: 9, minute: 0), intensity: .none)
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        #expect(plan.notifications.isEmpty)
        #expect(plan.alarms.isEmpty)
    }

    @Test("A completed occurrence schedules nothing further")
    func completedOccurrencesAreDropped() {
        let item = alertingItem(
            title: "Pills",
            at: TimeOfDay(hour: 20, minute: 0),
            nag: .every(10, upTo: 5)
        )
        let slot = Fixture.date(2026, 3, 10, 20, 0, calendar: calendar)
        let records = Fixture.records([
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: item.id, slot: slot),
                completedAt: now
            )
        ])
        let plan = engine().notificationPlan(items: [item], records: records, now: now)

        #expect(!plan.notifications.contains { calendar.isDate($0.fireDate, inSameDayAs: now) })
    }

    @Test("Every request for one occurrence shares a prefix, so completion can cancel them all")
    func identifiersShareAPrefix() {
        let item = alertingItem(
            title: "Pills",
            at: TimeOfDay(hour: 20, minute: 0),
            preAlerts: [600],
            nag: .every(10, upTo: 2)
        )
        let plan = engine().notificationPlan(items: [item], records: [:], now: now)
        let slot = Fixture.date(2026, 3, 10, 20, 0, calendar: calendar)
        let prefix = NotificationPlanner.prefix(for: OccurrenceKey(itemID: item.id, slot: slot))

        let todays = plan.notifications.filter { $0.id.hasPrefix(prefix) }
        #expect(todays.count == 4)  // one pre-alert, one primary, two nags
        #expect(Set(todays.map(\.id)).count == 4)
        // The fire time is part of the identifier, so moving an alert produces
        // a different request rather than leaving a stale one behind.
        #expect(todays.allSatisfy { $0.id.contains("@") })
        #expect(todays.allSatisfy { $0.id.hasPrefix(NotificationPlanner.itemPrefix(for: item.id)) })
    }
}
