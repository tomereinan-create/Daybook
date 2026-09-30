import Foundation
import Testing
@testable import Daybook

@Suite("Quota pacing")
struct QuotaPacerTests {
    let calendar = Fixture.calendar()

    /// The week of Sunday 1 March 2026.
    private var week: DateInterval {
        DateInterval(
            start: Fixture.date(2026, 3, 1, 0, 0, calendar: calendar),
            end: Fixture.date(2026, 3, 8, 0, 0, calendar: calendar)
        )
    }

    private var pacer: QuotaPacer { QuotaPacer(calendar: calendar) }

    @Test("Days remaining counts today, so the last day of the week reports one")
    func daysRemaining() {
        #expect(pacer.daysRemaining(in: week, at: Fixture.date(2026, 3, 1, 9, 0, calendar: calendar)) == 7)
        #expect(pacer.daysRemaining(in: week, at: Fixture.date(2026, 3, 5, 9, 0, calendar: calendar)) == 3)
        #expect(pacer.daysRemaining(in: week, at: Fixture.date(2026, 3, 7, 23, 0, calendar: calendar)) == 1)
        #expect(pacer.daysRemaining(in: week, at: Fixture.date(2026, 3, 8, 0, 1, calendar: calendar)) == 0)
    }

    @Test("Nothing is behind on the first day of the period")
    func notBehindOnDayOne() {
        let progress = pacer.progress(
            target: 3,
            completionsInPeriod: 0,
            period: week,
            now: Fixture.date(2026, 3, 1, 9, 0, calendar: calendar)
        )
        #expect(!progress.isBehindPace)
    }

    @Test("Three a week with nothing done by Thursday is behind")
    func behindByThursday() {
        let progress = pacer.progress(
            target: 3,
            completionsInPeriod: 0,
            period: week,
            now: Fixture.date(2026, 3, 5, 9, 0, calendar: calendar)
        )
        #expect(progress.isBehindPace)
        #expect(progress.completed == 0)
        #expect(progress.target == 3)
    }

    @Test("One done by Thursday still fits in the days that are left")
    func oneDoneIsStillOnPace() {
        let progress = pacer.progress(
            target: 3,
            completionsInPeriod: 1,
            period: week,
            now: Fixture.date(2026, 3, 5, 9, 0, calendar: calendar)
        )
        #expect(!progress.isBehindPace)
    }

    @Test("Meeting the quota stops the nudging entirely")
    func quotaMetIsNeverBehind() {
        let progress = pacer.progress(
            target: 3,
            completionsInPeriod: 3,
            period: week,
            now: Fixture.date(2026, 3, 7, 22, 0, calendar: calendar)
        )
        #expect(!progress.isBehindPace)
        #expect(progress.fractionComplete == 1.0)
    }

    @Test("One left on the last day is behind")
    func lastDayWithOneLeft() {
        let progress = pacer.progress(
            target: 3,
            completionsInPeriod: 2,
            period: week,
            now: Fixture.date(2026, 3, 7, 10, 0, calendar: calendar)
        )
        #expect(progress.isBehindPace)
    }
}

@Suite("Completion, routines and quotas")
struct CompletionServiceTests {
    let calendar = Fixture.calendar()
    let service = CompletionService()

    private var now: Date { Fixture.date(2026, 3, 10, 9, 0, calendar: calendar) }

    @Test("An ordinary item completes in one tap")
    func plainCompletion() {
        let item = Fixture.item(settings: .default, createdAt: now)
        let key = OccurrenceKey(itemID: item.id, slot: now)
        let (record, outcome) = service.complete(OccurrenceStateRecord(key: key), item: item, now: now)

        #expect(outcome == .completed)
        #expect(record.completedAt == now)
    }

    @Test("A routine advances one step per tap and only finishes on the last")
    func routineAdvancesStepByStep() {
        var settings = ItemSettings.default
        settings.steps = [Step(title: "Kettle"), Step(title: "Pills"), Step(title: "Shoes")]
        let item = Fixture.item(preset: .routine, settings: settings, createdAt: now)
        let key = OccurrenceKey(itemID: item.id, slot: now)

        var record = OccurrenceStateRecord(key: key)
        var outcomes: [CompletionOutcome] = []
        for _ in 0..<3 {
            let result = service.complete(record, item: item, now: now)
            record = result.record
            outcomes.append(result.outcome)
        }

        #expect(outcomes == [.advancedToStep(1), .advancedToStep(2), .completed])
        #expect(record.completedAt == now)
        #expect(record.currentStepIndex == 3)
    }

    @Test("The card shows the step the routine is on, not the whole routine")
    func routineShowsCurrentStep() {
        var settings = ItemSettings.default
        settings.trigger = .daily(at: TimeOfDay(hour: 7, minute: 0))
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: now)
        settings.steps = [Step(title: "Kettle"), Step(title: "Pills")]
        let item = Fixture.item(title: "Morning", preset: .routine, settings: settings, createdAt: now)

        let generated = OccurrenceGenerator(calendar: calendar).occurrences(
            for: item,
            in: calendar.startOfDay(for: now)..<calendar.startOfNextDay(after: now)
        )
        let record = OccurrenceStateRecord(key: generated[0].key, currentStepIndex: 1)
        let resolved = StateResolver(calendar: calendar).resolve(
            item: item,
            generated: generated[0],
            record: record,
            now: now
        )
        #expect(resolved.currentStep?.title == "Pills")
        #expect(resolved.displayTitle == "Morning: Pills")
    }

    @Test("A quota habit tallies until it hits its target")
    func quotaTalliesThenCompletes() {
        var settings = ItemSettings.default
        settings.recurrence = Recurrence(
            frequency: .quota(count: 3, period: .week),
            end: .never,
            anchorDate: now
        )
        let item = Fixture.item(preset: .flexibleHabit, settings: settings, createdAt: now)
        let key = OccurrenceKey(itemID: item.id, slot: now)

        var record = OccurrenceStateRecord(key: key)
        var outcomes: [CompletionOutcome] = []
        for _ in 0..<3 {
            let result = service.complete(record, item: item, now: now)
            record = result.record
            outcomes.append(result.outcome)
        }

        #expect(outcomes == [.tallied(count: 1, target: 3), .tallied(count: 2, target: 3), .completed])
        #expect(record.completionCount == 3)
        #expect(record.completedAt == now)
    }

    @Test("Reopening steps a routine and a quota back by one")
    func reopenStepsBack() {
        var settings = ItemSettings.default
        settings.steps = [Step(title: "A"), Step(title: "B")]
        let item = Fixture.item(settings: settings, createdAt: now)
        let key = OccurrenceKey(itemID: item.id, slot: now)
        let finished = OccurrenceStateRecord(key: key, completedAt: now, currentStepIndex: 2)

        let reopened = service.reopen(finished, item: item)
        #expect(reopened.completedAt == nil)
        #expect(reopened.currentStepIndex == 1)
    }

    @Test("Snooze is refused when the item does not allow it")
    func snoozeRespectsTheSetting() {
        var settings = ItemSettings.default
        settings.alerting.snoozeAllowed = false
        let item = Fixture.item(settings: settings, createdAt: now)
        let key = OccurrenceKey(itemID: item.id, slot: now)

        #expect(service.snooze(OccurrenceStateRecord(key: key), item: item, now: now) == nil)

        var allowed = settings
        allowed.alerting.snoozeAllowed = true
        allowed.alerting.snoozeMinutes = 12
        let snoozable = Fixture.item(settings: allowed, createdAt: now)
        let result = service.snooze(OccurrenceStateRecord(key: key), item: snoozable, now: now)
        #expect(result?.snoozedUntil == now.addingTimeInterval(12 * 60))
    }

    @Test("Only a relative timer can be started, and only once")
    func startOnlyAppliesToTimers() {
        let plain = Fixture.item(settings: .default, createdAt: now)
        let key = OccurrenceKey(itemID: plain.id, slot: now)
        #expect(service.start(OccurrenceStateRecord(key: key), item: plain, now: now) == nil)

        var settings = ItemSettings.default
        settings.trigger = .minutesAfterStart(30)
        let timer = Fixture.item(settings: settings, createdAt: now)
        let started = service.start(OccurrenceStateRecord(key: key), item: timer, now: now)
        #expect(started?.startedAt == now)
        #expect(service.start(started!, item: timer, now: now) == nil)
    }
}

@Suite("Done starts a clock when the item runs for a while")
struct HoldTimerTests {
    let calendar = Fixture.calendar()
    let completion = CompletionService()
    let resolver = StateResolver(calendar: Fixture.calendar())
    private var now: Date { Fixture.date(2026, 3, 10, 8, 0, calendar: calendar) }

    private func brushing() -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.holdMinutes = 2
        return Fixture.item(title: "Brush teeth", settings: settings, createdAt: now)
    }

    @Test("Done sets the clock rather than finishing it")
    func doneStartsTheClock() {
        let item = brushing()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let (record, outcome) = completion.complete(OccurrenceStateRecord(key: key), item: item, now: now)

        #expect(record.completedAt == nil)
        #expect(record.holdUntil == now.addingTimeInterval(120))
        #expect(outcome == .holding(until: now.addingTimeInterval(120)))
    }

    @Test("It is being done while the clock runs, and done when it stops")
    func theClockDecidesTheState() {
        let item = brushing()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let running = OccurrenceStateRecord(key: key, holdUntil: now.addingTimeInterval(120))
        let generated = GeneratedOccurrence(key: key, triggerDate: nil, ordinal: 0, quotaPeriod: nil)

        let midway = resolver.resolve(
            item: item, generated: generated, record: running,
            now: now.addingTimeInterval(60)
        )
        #expect(midway.state == .active)

        let after = resolver.resolve(
            item: item, generated: generated, record: running,
            now: now.addingTimeInterval(121)
        )
        #expect(after.state == .done)
    }

    @Test("A second tap finishes early rather than restarting the clock")
    func tappingAgainFinishesIt() {
        let item = brushing()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let running = OccurrenceStateRecord(key: key, holdUntil: now.addingTimeInterval(120))

        let (record, outcome) = completion.complete(
            running, item: item, now: now.addingTimeInterval(30)
        )
        #expect(record.holdUntil == nil)
        #expect(record.completedAt == now.addingTimeInterval(30))
        #expect(outcome == .completed)
    }

    @Test("An elapsed clock is written out as a completion at the moment it ran out")
    func elapsedHoldsSettle() {
        let item = brushing()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let ranOut = now.addingTimeInterval(120)
        let records = [key: OccurrenceStateRecord(key: key, holdUntil: ranOut)]

        // Still running: nothing to write.
        #expect(completion.settleElapsedHolds(records, now: now.addingTimeInterval(60)).isEmpty)

        // Finished an hour ago, because the app was closed. It completed when
        // the clock ran out, not when the app noticed.
        let settled = completion.settleElapsedHolds(records, now: now.addingTimeInterval(3600))
        #expect(settled[key]?.completedAt == ranOut)
        #expect(settled[key]?.holdUntil == nil)
    }

    @Test("Undo stops the clock")
    func reopeningClearsTheHold() {
        let item = brushing()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let running = OccurrenceStateRecord(key: key, holdUntil: now.addingTimeInterval(120))
        #expect(completion.reopen(running, item: item).holdUntil == nil)
    }

    @Test("A held item can always say when its clock ran out")
    func aHeldItemCanAlert() {
        var settings = ItemSettings.default
        // Display only, no trigger: the quietest an item gets.
        #expect(!settings.canAlert)
        settings.holdMinutes = 2
        #expect(settings.canAlert)
    }
}

@Suite("Answering an item with a number or a word")
struct ResponseTests {
    let calendar = Fixture.calendar()
    let completion = CompletionService()
    private var now: Date { Fixture.date(2026, 3, 10, 8, 0, calendar: calendar) }

    private func weighIn() -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.response = .number
        return Fixture.item(title: "Weight", settings: settings, createdAt: now)
    }

    @Test("The answer is kept with the occurrence, not the item")
    func theAnswerIsPerOccurrence() {
        let item = weighIn()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let (record, _) = completion.complete(
            OccurrenceStateRecord(key: key), item: item, now: now, answer: "78.1"
        )
        #expect(record.answer == "78.1")
        #expect(record.completedAt == now)
    }

    @Test("Whitespace is not an answer")
    func blankAnswersAreNotKept() {
        let item = weighIn()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let (record, _) = completion.complete(
            OccurrenceStateRecord(key: key), item: item, now: now, answer: "   "
        )
        #expect(record.answer == nil)
    }

    @Test("Finishing without being asked leaves an earlier answer alone")
    func completingWithoutAnAnswerKeepsTheOldOne() {
        let item = weighIn()
        let key = OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: now))
        let existing = OccurrenceStateRecord(key: key, answer: "77.4")
        let (record, _) = completion.complete(existing, item: item, now: now)
        #expect(record.answer == "77.4")
    }

    @Test("Nothing asks for an answer unless it was set to")
    func nothingAsksByDefault() {
        #expect(ItemSettings.default.answerKind == .none)
        #expect(!ItemSettings.default.answerKind.asksForAnything)
        for preset in PresetKind.allCases {
            let settings = preset.defaultSettings(reference: now, calendar: calendar)
            #expect(settings.answerKind == .none)
            #expect(settings.holdDuration == nil)
        }
    }
}
