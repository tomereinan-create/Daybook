import Foundation
import Testing
@testable import Daybook

@Suite("Daylight saving, midnight and time zones")
struct TimeZoneAndDSTTests {
    /// New York springs forward on 2026-03-08 and falls back on 2026-11-01.
    let newYork = Fixture.calendar(timeZone: "America/New_York")
    let jerusalem = Fixture.calendar(timeZone: "Asia/Jerusalem")

    @Test("A 07:00 daily item stays at 07:00 local across the spring-forward day")
    func springForwardKeepsWallClockTime() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: newYork)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 7, minute: 0), from: anchor)

        let start = Fixture.date(2026, 3, 6, 0, 0, calendar: newYork)
        let end = Fixture.date(2026, 3, 11, 0, 0, calendar: newYork)
        let occurrences = OccurrenceGenerator(calendar: newYork).occurrences(for: item, in: start..<end)
        #expect(occurrences.count == 5)
        for occurrence in occurrences {
            #expect(newYork.component(.hour, from: occurrence.slot) == 7)
            #expect(newYork.component(.minute, from: occurrence.slot) == 0)
        }

        // The real elapsed time across the transition is an hour shorter.
        let saturday = occurrences[1].slot   // 7 March
        let sunday = occurrences[2].slot     // 8 March, the short day
        #expect(sunday.timeIntervalSince(saturday) == 23 * 3600)
    }

    @Test("A 02:30 item on the spring-forward day still fires exactly once")
    func springForwardMissingHourFiresOnce() {
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: newYork)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 2, minute: 30), from: anchor)

        let start = Fixture.date(2026, 3, 8, 0, 0, calendar: newYork)
        let end = Fixture.date(2026, 3, 9, 0, 0, calendar: newYork)
        let occurrences = OccurrenceGenerator(calendar: newYork).occurrences(for: item, in: start..<end)
        // What matters is that the missing hour neither swallows the
        // occurrence nor produces two. Foundation snaps the nonexistent 02:30
        // to one side of the gap; we assert only that it landed outside it,
        // on the right day.
        #expect(occurrences.count == 1)
        let hour = newYork.component(.hour, from: occurrences[0].slot)
        #expect(hour != 2)
        #expect(newYork.component(.day, from: occurrences[0].slot) == 8)
    }

    @Test("A 07:00 daily item stays at 07:00 local across the fall-back day")
    func fallBackKeepsWallClockTime() {
        let anchor = Fixture.date(2026, 10, 1, 0, 0, calendar: newYork)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 7, minute: 0), from: anchor)

        let start = Fixture.date(2026, 10, 31, 0, 0, calendar: newYork)
        let end = Fixture.date(2026, 11, 3, 0, 0, calendar: newYork)
        let occurrences = OccurrenceGenerator(calendar: newYork).occurrences(for: item, in: start..<end)
        #expect(occurrences.count == 3)
        for occurrence in occurrences {
            #expect(newYork.component(.hour, from: occurrence.slot) == 7)
        }
        let saturday = occurrences[0].slot   // 31 October
        let sunday = occurrences[1].slot     // 1 November, the long day
        #expect(sunday.timeIntervalSince(saturday) == 25 * 3600)
    }

    @Test("The same item read in another time zone fires at 07:00 there")
    func timeZoneChangeMovesTheAlarm() {
        let anchor = Fixture.date(2026, 6, 1, 0, 0, calendar: newYork)
        let item = Fixture.dailyItem(at: TimeOfDay(hour: 7, minute: 0), from: anchor)
        let start = Fixture.date(2026, 6, 10, 0, 0, calendar: newYork)
        let end = Fixture.date(2026, 6, 11, 0, 0, calendar: newYork)
        let range = start..<end

        let inNewYork = OccurrenceGenerator(calendar: newYork).occurrences(for: item, in: range)
        let inJerusalem = OccurrenceGenerator(calendar: jerusalem).occurrences(for: item, in: range)

        #expect(inNewYork.count == 1)
        #expect(inJerusalem.count >= 1)
        #expect(newYork.component(.hour, from: inNewYork[0].slot) == 7)
        #expect(jerusalem.component(.hour, from: inJerusalem[0].slot) == 7)
        // Same wall-clock time, different instants: that is the whole point.
        #expect(inNewYork[0].slot != inJerusalem[0].slot)
    }

    @Test("A window that crosses midnight is still active after midnight")
    func windowCrossesMidnight() {
        let calendar = Fixture.calendar()
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 23, minute: 50),
            from: anchor,
            endCondition: .windowEnds(30 * 60)
        )
        let start = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let end = Fixture.date(2026, 3, 11, 0, 0, calendar: calendar)
        let generated = OccurrenceGenerator(calendar: calendar).occurrences(for: item, in: start..<end)
        #expect(generated.count == 1)

        let resolver = StateResolver(calendar: calendar)
        let justAfterMidnight = Fixture.date(2026, 3, 11, 0, 5, calendar: calendar)
        let resolved = resolver.resolve(
            item: item,
            generated: generated[0],
            record: nil,
            now: justAfterMidnight
        )
        #expect(resolved.state == .active)

        let afterWindow = Fixture.date(2026, 3, 11, 0, 25, calendar: calendar)
        let expired = resolver.resolve(
            item: item,
            generated: generated[0],
            record: nil,
            now: afterWindow
        )
        #expect(expired.state == .missed)
    }

    @Test("A disappear-at time earlier than the trigger rolls to the next day")
    func disappearAtTimeRollsOver() {
        let calendar = Fixture.calendar()
        let anchor = Fixture.date(2026, 3, 1, 0, 0, calendar: calendar)
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 22, minute: 0),
            from: anchor,
            endCondition: .atTime(TimeOfDay(hour: 6, minute: 0))
        )
        let start = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let end = Fixture.date(2026, 3, 11, 0, 0, calendar: calendar)
        let generated = OccurrenceGenerator(calendar: calendar).occurrences(for: item, in: start..<end)
        let resolver = StateResolver(calendar: calendar)
        let window = resolver.windowEnd(
            for: item,
            trigger: generated[0].slot,
            generated: generated[0]
        )
        #expect(window == Fixture.date(2026, 3, 11, 6, 0, calendar: calendar))
    }
}
