import Foundation
import Testing
@testable import Daybook

@Suite("Occurrence generation")
struct OccurrenceGeneratorTests {
    let calendar = Fixture.calendar()

    private func generator() -> OccurrenceGenerator {
        OccurrenceGenerator(calendar: calendar)
    }

    @Test("A one-off item produces exactly one occurrence, inside its range")
    func onceInRange() {
        let anchor = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let trigger = Fixture.date(2026, 3, 12, 9, 30, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .at(trigger)
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let inside = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 3, 11, 0, 0, calendar: calendar)..<Fixture.date(2026, 3, 14, 0, 0, calendar: calendar)
        )
        #expect(inside.count == 1)
        #expect(inside.first?.triggerDate == trigger)

        let outside = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 4, 1, 0, 0, calendar: calendar)..<Fixture.date(2026, 4, 3, 0, 0, calendar: calendar)
        )
        #expect(outside.isEmpty)
    }

    @Test("An undated task has one stable slot regardless of range")
    func undatedTaskHasOneSlot() {
        let created = Fixture.date(2026, 3, 10, 14, 22, calendar: calendar)
        let item = Fixture.item(settings: .default, createdAt: created)

        let occurrences = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)..<Fixture.date(2026, 4, 1, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.triggerDate == nil)
        #expect(occurrences.first?.slot == calendar.startOfDay(for: created))
    }

    @Test("Daily recurrence fills every day in range at the right wall-clock time")
    func dailyFillsRange() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 7, minute: 15), from: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)..<Fixture.date(2026, 3, 15, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 5)
        for occurrence in occurrences {
            #expect(calendar.component(.hour, from: occurrence.slot) == 7)
            #expect(calendar.component(.minute, from: occurrence.slot) == 15)
        }
        #expect(occurrences.map(\.ordinal) == [9, 10, 11, 12, 13])
    }

    @Test("Nothing is generated before the anchor date")
    func nothingBeforeAnchor() {
        let anchor = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 8, minute: 0), from: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 3, 5, 0, 0, calendar: calendar)..<Fixture.date(2026, 3, 13, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 3)
        #expect(occurrences.first?.ordinal == 0)
    }

    @Test("Specific weekdays only land on those days, and ordinals keep counting")
    func weekdaysOnly() {
        // 2026-03-01 is a Sunday.
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 9, minute: 0))
        settings.recurrence = Recurrence(
            frequency: .weekdays([.monday, .wednesday, .friday]),
            end: .never,
            anchorDate: anchor
        )
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 3, 15, 0, 0, calendar: calendar)
        )
        let weekdays = Set(occurrences.map { calendar.weekday(of: $0.slot) })
        #expect(weekdays == [.monday, .wednesday, .friday])
        #expect(occurrences.count == 6)
        #expect(occurrences.map(\.ordinal) == [0, 1, 2, 3, 4, 5])
    }

    @Test("Every N days counts from the anchor, not from the range")
    func everyNDays() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 6, minute: 0))
        settings.recurrence = Recurrence(frequency: .everyNDays(3), end: .never, anchorDate: anchor)
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 3, 8, 0, 0, calendar: calendar)..<Fixture.date(2026, 3, 18, 0, 0, calendar: calendar)
        )
        let days = occurrences.map { calendar.component(.day, from: $0.slot) }
        #expect(days == [10, 13, 16])
        #expect(occurrences.map(\.ordinal) == [3, 4, 5])
    }

    @Test("Day 31 clamps to the last day of shorter months")
    func dayOfMonthClamps() {
        let anchor = Fixture.date(2026, 1, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 12, minute: 0))
        settings.recurrence = Recurrence(frequency: .dayOfMonth(31), end: .never, anchorDate: anchor)
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 5, 1, 0, 0, calendar: calendar)
        )
        let stamps = occurrences.map {
            (calendar.component(.month, from: $0.slot), calendar.component(.day, from: $0.slot))
        }
        // 2026 is not a leap year, so February clamps to the 28th.
        #expect(stamps.count == 4)
        #expect(stamps[0] == (1, 31))
        #expect(stamps[1] == (2, 28))
        #expect(stamps[2] == (3, 31))
        #expect(stamps[3] == (4, 30))
        #expect(occurrences.map(\.ordinal) == [0, 1, 2, 3])
    }

    @Test("An until date stops the series on that day")
    func untilDateStops() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 8, minute: 0))
        settings.recurrence = Recurrence(
            frequency: .daily,
            end: .until(Fixture.date(2026, 3, 5, 0, 0, calendar: calendar)),
            anchorDate: anchor
        )
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 3, 20, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 5)
        #expect(calendar.component(.day, from: occurrences.last!.slot) == 5)
    }

    @Test("After N occurrences stops at exactly N")
    func afterCountStops() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 8, minute: 0))
        settings.recurrence = Recurrence(frequency: .daily, end: .afterOccurrences(3), anchorDate: anchor)
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 4, 1, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 3)
        #expect(occurrences.map(\.ordinal) == [0, 1, 2])
    }

    @Test("A weekly quota produces one bucket per week with no trigger time")
    func quotaBuckets() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 3, period: .week),
            end: .never,
            anchorDate: anchor
        )
        let item = Fixture.item(settings: settings, createdAt: anchor)

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 3, 22, 0, 0, calendar: calendar)
        )
        #expect(occurrences.count == 3)
        #expect(occurrences.allSatisfy { $0.triggerDate == nil })
        #expect(occurrences.allSatisfy { $0.quotaPeriod != nil })
        for occurrence in occurrences {
            let period = occurrence.quotaPeriod!
            #expect(period.duration == 7 * 24 * 3600)
        }
    }

    @Test("A quota habit started mid-week counts that week, not the next one")
    func quotaCountsTheWeekItWasCreatedIn() {
        // Created on a Tuesday. The week holding it began on the Sunday, two
        // days before the anchor, and it still has to be this week's quota.
        let created = Fixture.date(2026, 3, 10, 14, 30, calendar: calendar)
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 3, period: .week),
            end: .never,
            anchorDate: created
        )
        let item = Fixture.item(title: "Gym", preset: .flexibleHabit, settings: settings, createdAt: created)

        let start = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let end = Fixture.date(2026, 3, 12, 0, 0, calendar: calendar)
        let occurrences = generator().occurrences(for: item, in: start..<end)

        #expect(occurrences.count == 1)
        #expect(occurrences.first?.ordinal == 0)
        #expect(occurrences.first?.quotaPeriod?.start == Fixture.date(2026, 3, 8, 0, 0, calendar: calendar))
        // Weeks entirely before the anchor are still left alone.
        let older = generator().occurrences(
            for: item,
            in: Fixture.date(2026, 2, 1, 0, 0, calendar: calendar)..<Fixture.date(2026, 3, 8, 0, 0, calendar: calendar)
        )
        #expect(older.isEmpty)
    }

    @Test("A monthly quota started mid-month counts that month")
    func monthlyQuotaCountsTheMonthItWasCreatedIn() {
        let created = Fixture.date(2026, 3, 20, 9, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 2, period: .month),
            end: .never,
            anchorDate: created
        )
        let item = Fixture.item(title: "Call home", preset: .flexibleHabit, settings: settings, createdAt: created)

        let start = Fixture.date(2026, 3, 20, 0, 0, calendar: calendar)
        let end = Fixture.date(2026, 3, 25, 0, 0, calendar: calendar)
        let occurrences = generator().occurrences(for: item, in: start..<end)

        #expect(occurrences.count == 1)
        #expect(occurrences.first?.quotaPeriod?.start == Fixture.date(2026, 3, 1, 0, 0, calendar: calendar))
    }

    @Test("An archived item generates nothing")
    func archivedGeneratesNothing() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 8, minute: 0))
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
        let item = ItemSnapshot(
            title: "Archived",
            settings: settings,
            isArchived: true,
            createdAt: anchor
        )

        let occurrences = generator().occurrences(
            for: item,
            in: anchor..<Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        )
        #expect(occurrences.isEmpty)
    }
}
