import Foundation
import Testing
@testable import Daybook

@Suite("The weekly review")
struct WeekReviewTests {
    let calendar = Fixture.calendar()

    /// Tuesday 10 March 2026, in the week beginning Sunday the 8th.
    private var now: Date { Fixture.date(2026, 3, 10, 12, 0, calendar: calendar) }
    private var anchor: Date { Fixture.date(2026, 3, 1, 0, 0, calendar: calendar) }

    private var engine: ScheduleEngine {
        ScheduleEngine(calendar: calendar, configuration: .default, quietHours: .default)
    }

    private func dated(_ title: String, at date: Date, dismissal: Dismissal = .untilDone) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.trigger = .at(date)
        settings.dismissal = dismissal
        return Fixture.item(title: title, settings: settings, createdAt: anchor)
    }

    @Test("Completed and missed are counted over this week only")
    func countsThisWeek() {
        let thisWeek = dated("Monday thing", at: Fixture.date(2026, 3, 9, 9, 0, calendar: calendar))
        let lastWeek = dated("Last week", at: Fixture.date(2026, 3, 3, 9, 0, calendar: calendar))
        let records = Fixture.records([
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: thisWeek.id, slot: Fixture.date(2026, 3, 9, 9, 0, calendar: calendar)),
                completedAt: Fixture.date(2026, 3, 9, 9, 5, calendar: calendar)
            ),
            OccurrenceStateRecord(
                key: OccurrenceKey(itemID: lastWeek.id, slot: Fixture.date(2026, 3, 3, 9, 0, calendar: calendar)),
                completedAt: Fixture.date(2026, 3, 3, 9, 5, calendar: calendar)
            )
        ])

        let review = engine.weekReview(items: [thisWeek, lastWeek], records: records, now: now)
        #expect(review.completed == 1)
        #expect(review.week.start == Fixture.date(2026, 3, 8, 0, 0, calendar: calendar))
    }

    @Test("An event that simply started is not counted as missed")
    func eventsAreNotMissed() {
        let event = dated(
            "Stand-up",
            at: Fixture.date(2026, 3, 9, 9, 0, calendar: calendar),
            dismissal: .atEventStart
        )
        let deadline = dated(
            "Physio",
            at: Fixture.date(2026, 3, 9, 9, 0, calendar: calendar),
            dismissal: Dismissal(endCondition: .windowEnds(3600), onMissed: .logMissed)
        )

        let review = engine.weekReview(items: [event, deadline], records: [:], now: now)
        // Both windows closed unfinished; only the one that owed something counts.
        #expect(review.missed == 1)
    }

    @Test("A habit behind its pace is surfaced")
    func behindHabitsAreSurfaced() {
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 3, period: .week),
            end: .never,
            anchorDate: anchor
        )
        settings.visibility = Visibility(leadTime: 0, surfaces: .all)
        let gym = Fixture.item(title: "Gym", preset: .flexibleHabit, settings: settings, createdAt: anchor)

        // Tuesday, nothing done, three owed and five days left: still fine.
        let early = engine.weekReview(items: [gym], records: [:], now: now)
        #expect(early.behind.isEmpty)

        // Friday, still nothing done: three owed, three days left.
        let friday = Fixture.date(2026, 3, 13, 12, 0, calendar: calendar)
        let late = engine.weekReview(items: [gym], records: [:], now: friday)
        #expect(late.behind.count == 1)
    }

    @Test("Waiting-for items are ordered by how long they have been quiet")
    func waitingIsOrderedBySilence() {
        func waiting(_ title: String, created: Date) -> ItemSnapshot {
            var settings = PresetKind.waitingFor.defaultSettings(reference: created, calendar: calendar)
            settings.alerting.nag = .every(3 * 24 * 60, upTo: 5)
            return Fixture.item(title: title, preset: .waitingFor, settings: settings, createdAt: created)
        }
        let plumber = waiting("Plumber", created: Fixture.date(2026, 3, 5, 9, 0, calendar: calendar))
        let sarah = waiting("Sarah", created: Fixture.date(2026, 3, 9, 9, 0, calendar: calendar))

        let review = engine.weekReview(items: [sarah, plumber], records: [:], now: now)
        #expect(review.waiting.map(\.item.title) == ["Plumber", "Sarah"])
        #expect(review.waiting[0].daysQuiet == 5)
        #expect(review.waiting[0].isOverdue)
        #expect(!review.waiting[1].isOverdue)
    }

    @Test("Someday items appear here and nowhere else")
    func somedaySurfacesOnlyInTheReview() {
        let settings = PresetKind.someday.defaultSettings(reference: anchor, calendar: calendar)
        let sail = Fixture.item(title: "Learn to sail", preset: .someday, settings: settings, createdAt: anchor)

        let review = engine.weekReview(items: [sail], records: [:], now: now)
        #expect(review.someday.map(\.title) == ["Learn to sail"])

        // Still absent from the day and from every live surface.
        let plan = engine.dayPlan(items: [sail], records: [:], on: now, now: now)
        #expect(plan.outstandingCount == 0)
        #expect(engine.entries(for: .homeWidget, items: [sail], records: [:], now: now).isEmpty)
    }

    @Test("An empty week says so rather than showing zeroes")
    func emptyWeekIsRecognisable() {
        let review = engine.weekReview(items: [], records: [:], now: now)
        #expect(!review.hasAnythingToSay)
    }
}
