import Foundation
import Testing
@testable import Daybook

@Suite("Occurrence state")
struct StateResolverTests {
    let calendar = Fixture.calendar()
    let resolver = StateResolver(calendar: Fixture.calendar())

    private func generated(_ item: ItemSnapshot, on day: Date) -> GeneratedOccurrence {
        let range = calendar.startOfDay(for: day)..<calendar.startOfNextDay(after: day)
        let list = OccurrenceGenerator(calendar: calendar).occurrences(for: item, in: range)
        guard let first = list.first else {
            fatalError("Expected an occurrence on \(day)")
        }
        return first
    }

    @Test("Before the lead time an occurrence is upcoming, inside it it is visible")
    func leadTimeMakesItVisible() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 12, minute: 0),
            from: anchor,
            leadTime: 2 * 3600
        )
        let day = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let occurrence = generated(item, on: day)

        let early = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        )
        #expect(early.state == .upcoming)

        let inLead = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 10, 30, calendar: calendar)
        )
        #expect(inLead.state == .visible)
    }

    @Test("Due inside the grace period, overdue after it")
    func dueThenOverdue() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 12, minute: 0), from: anchor)
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))

        let due = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 12, 5, calendar: calendar)
        )
        #expect(due.state == .due)

        let overdue = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 13, 0, calendar: calendar)
        )
        #expect(overdue.state == .overdue)
    }

    @Test("A time block is active for its window and then disappears")
    func timeBlockIsActiveThenMissed() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 9, minute: 0),
            from: anchor,
            endCondition: .windowEnds(3600)
        )
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))

        let during = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 9, 30, calendar: calendar)
        )
        #expect(during.state == .active)
        #expect(during.windowEnd == Fixture.date(2026, 3, 10, 10, 0, calendar: calendar))

        let after = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 10, 1, calendar: calendar)
        )
        #expect(after.state == .missed)
    }

    @Test("An item that becomes an open task stays overdue rather than missed")
    func openTaskStaysOverdue() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 9, minute: 0),
            from: anchor,
            endCondition: .windowEnds(3600),
            onMissed: .becomeOpenTask
        )
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))

        let wayLater = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 12, 15, 0, calendar: calendar)
        )
        #expect(wayLater.state == .overdue)
        #expect(wayLater.state.isOutstanding)
    }

    @Test("Roll-over walks the trigger forward a day at a time until it is done")
    func rollOverMovesToTheNextDay() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 9, minute: 0),
            from: anchor,
            endCondition: .windowEnds(3600),
            onMissed: .rollOver
        )
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))

        let twoDaysLater = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 12, 9, 30, calendar: calendar)
        )
        #expect(twoDaysLater.effectiveTrigger == Fixture.date(2026, 3, 12, 9, 0, calendar: calendar))
        #expect(twoDaysLater.state == .active)
    }

    @Test("Completing an occurrence makes it done whatever the clock says")
    func completionWins() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 9, minute: 0), from: anchor)
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))
        let record = OccurrenceStateRecord(
            key: occurrence.key,
            completedAt: Fixture.date(2026, 3, 10, 9, 2, calendar: calendar)
        )

        let resolved = resolver.resolve(
            item: item,
            generated: occurrence,
            record: record,
            now: Fixture.date(2026, 3, 15, 9, 0, calendar: calendar)
        )
        #expect(resolved.state == .done)
    }

    @Test("Snoozing hides the occurrence and moves its trigger")
    func snoozeMovesTheTrigger() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 9, minute: 0), from: anchor)
        let occurrence = generated(item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))
        let snoozedUntil = Fixture.date(2026, 3, 10, 9, 20, calendar: calendar)
        let record = OccurrenceStateRecord(key: occurrence.key, snoozedUntil: snoozedUntil)

        let whileSnoozed = resolver.resolve(
            item: item,
            generated: occurrence,
            record: record,
            now: Fixture.date(2026, 3, 10, 9, 10, calendar: calendar)
        )
        #expect(whileSnoozed.state == .snoozed)
        #expect(whileSnoozed.effectiveTrigger == snoozedUntil)
        #expect(!whileSnoozed.state.appearsOnLiveSurfaces)

        let afterSnooze = resolver.resolve(
            item: item,
            generated: occurrence,
            record: record,
            now: Fixture.date(2026, 3, 10, 9, 25, calendar: calendar)
        )
        #expect(afterSnooze.state == .due)
    }

    @Test("A relative timer is visible until started, then counts down")
    func relativeTimerNeedsStarting() {
        let created = Fixture.date(2026, 3, 10, 8, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .minutesAfterStart(45)
        settings.visibility = Visibility(leadTime: 0, surfaces: .all)
        let item = Fixture.item(preset: .relativeTimer, settings: settings, createdAt: created)
        let occurrence = generated(item, on: created)

        let unstarted = resolver.resolve(item: item, generated: occurrence, record: nil, now: created)
        #expect(unstarted.state == .visible)
        #expect(unstarted.effectiveTrigger == nil)

        let started = OccurrenceStateRecord(
            key: occurrence.key,
            startedAt: Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        )
        let running = resolver.resolve(
            item: item,
            generated: occurrence,
            record: started,
            now: Fixture.date(2026, 3, 10, 9, 30, calendar: calendar)
        )
        #expect(running.effectiveTrigger == Fixture.date(2026, 3, 10, 9, 45, calendar: calendar))
        // Running, not merely upcoming: a started timer stays on screen even
        // though the item has no lead time at all.
        #expect(running.state == .active)
        #expect(running.state.appearsOnLiveSurfaces)

        let fired = resolver.resolve(
            item: item,
            generated: occurrence,
            record: started,
            now: Fixture.date(2026, 3, 10, 9, 50, calendar: calendar)
        )
        #expect(fired.state == .due)
    }

    @Test("An event files under Earlier rather than Missed once it has started")
    func eventConcludesNaturally() {
        let created = Fixture.date(2026, 3, 10, 8, 0, calendar: calendar)
        var settings = PresetKind.event.defaultSettings(reference: created, calendar: calendar)
        settings.trigger = .at(Fixture.date(2026, 3, 10, 14, 0, calendar: calendar))
        let item = Fixture.item(preset: .event, settings: settings, createdAt: created)
        let occurrence = generated(item, on: created)

        let afterStart = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 3, 10, 14, 30, calendar: calendar)
        )
        #expect(afterStart.state == .missed)
        #expect(afterStart.concludedNaturally)
        #expect(afterStart.daySection == .done)
    }

    @Test("An undated task is visible forever until it is completed")
    func undatedTaskStaysVisible() {
        let created = Fixture.date(2026, 3, 10, 8, 0, calendar: calendar)
        let item = Fixture.item(settings: .default, createdAt: created)
        let occurrence = generated(item, on: created)

        let muchLater = resolver.resolve(
            item: item,
            generated: occurrence,
            record: nil,
            now: Fixture.date(2026, 9, 1, 8, 0, calendar: calendar)
        )
        #expect(muchLater.state == .visible)
        #expect(muchLater.daySection == .undated)
    }
}
