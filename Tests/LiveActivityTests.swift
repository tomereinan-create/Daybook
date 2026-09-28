import Foundation
import Testing
@testable import Daybook

@Suite("What the push carries")
struct LiveActivityContentTests {
    let calendar = Fixture.calendar()

    private func item(_ title: String, at trigger: Date?) -> LiveItem {
        LiveItem(
            itemID: UUID().uuidString,
            slot: trigger?.timeIntervalSince1970 ?? 0,
            title: title,
            subtitle: nil,
            triggerDate: trigger,
            windowEnd: nil,
            stateRaw: OccurrenceState.visible.rawValue,
            isMandatory: false,
            snoozeMinutes: 10
        )
    }

    private var day: [LiveItem] {
        [
            item("Pills", at: Fixture.date(2026, 3, 10, 7, 0, calendar: calendar)),
            item("Dentist", at: Fixture.date(2026, 3, 10, 8, 30, calendar: calendar)),
            item("Stand-up", at: Fixture.date(2026, 3, 10, 9, 30, calendar: calendar))
        ]
    }

    @Test("Before the day starts, the card leads with the first item")
    func beforeTheDayStarts() {
        let state = DaybookActivityAttributes.ContentState.at(
            Fixture.date(2026, 3, 10, 6, 0, calendar: calendar),
            items: day, doneCount: 0, totalCount: 3
        )
        #expect(state.currentIndex == 0)
    }

    @Test("The current item is the last one whose moment has arrived")
    func advancesWithTheDay() {
        let items = day
        let cases: [(hour: Int, minute: Int, expected: Int)] = [
            (7, 1, 0),
            (8, 29, 0),
            (8, 31, 1),
            (9, 31, 2),
            (23, 0, 2)
        ]
        for testCase in cases {
            let state = DaybookActivityAttributes.ContentState.at(
                Fixture.date(2026, 3, 10, testCase.hour, testCase.minute, calendar: calendar),
                items: items, doneCount: 0, totalCount: 3
            )
            #expect(state.currentIndex == testCase.expected)
        }
    }

    @Test("Undated items never become the current one on their own")
    func undatedItemsDoNotAdvanceTheCard() {
        let items = [
            item("Pills", at: Fixture.date(2026, 3, 10, 7, 0, calendar: calendar)),
            item("Renew passport", at: nil)
        ]
        let state = DaybookActivityAttributes.ContentState.at(
            Fixture.date(2026, 3, 10, 23, 0, calendar: calendar),
            items: items, doneCount: 0, totalCount: 2
        )
        #expect(state.currentIndex == 0)
    }

    @Test("Attributes resolve the index back to an item, and to what follows")
    func attributesResolveTheIndex() {
        let attributes = DaybookActivityAttributes(
            day: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar),
            items: day
        )
        let state = DaybookActivityAttributes.ContentState(currentIndex: 1, doneCount: 1, totalCount: 3)

        #expect(attributes.current(at: state)?.title == "Dentist")
        #expect(attributes.upcoming(at: state).map(\.title) == ["Stand-up"])

        // Past the end is the finished day, not a crash.
        let finished = DaybookActivityAttributes.ContentState(currentIndex: 9, doneCount: 3, totalCount: 3)
        #expect(attributes.current(at: finished) == nil)
        #expect(attributes.upcoming(at: finished).isEmpty)
    }

    @Test("The schedule the server gets has times and indices, and nothing else")
    func scheduleCarriesNoContent() throws {
        let now = Fixture.date(2026, 3, 10, 8, 0, calendar: calendar)
        let schedule = PushSchedule.from(items: day, doneCount: 1, totalCount: 3, after: now)

        // Only what is still ahead: 07:00 has already gone.
        #expect(schedule.steps.count == 2)
        #expect(schedule.steps.map(\.index) == [1, 2])

        // The wire format is the real test of the privacy claim.
        let json = try String(data: JSONEncoder().encode(schedule), encoding: .utf8) ?? ""
        for title in ["Pills", "Dentist", "Stand-up"] {
            #expect(!json.contains(title))
        }
    }

    @Test("A registration is a token and a schedule, and carries no titles")
    func registrationCarriesNoContent() throws {
        let now = Fixture.date(2026, 3, 10, 6, 0, calendar: calendar)
        let registration = PushRegistration(
            token: "abc123",
            schedule: PushSchedule.from(items: day, doneCount: 0, totalCount: 3, after: now)
        )
        let json = try String(data: JSONEncoder().encode(registration), encoding: .utf8) ?? ""

        #expect(json.contains("abc123"))
        for title in ["Pills", "Dentist", "Stand-up"] {
            #expect(!json.contains(title))
        }
    }

    @Test("The index the server sends matches the index the app would compute")
    func serverAndAppAgree() {
        let items = day
        let start = Fixture.date(2026, 3, 10, 0, 0, calendar: calendar)
        let schedule = PushSchedule.from(items: items, doneCount: 0, totalCount: 3, after: start)

        // At each moment the server will push, the app's own rule must produce
        // the same index — otherwise the card would jump when the app next ran.
        for step in schedule.steps {
            let moment = Date(timeIntervalSince1970: step.at)
            let computed = DaybookActivityAttributes.ContentState.at(
                moment, items: items, doneCount: 0, totalCount: 3
            )
            #expect(computed.currentIndex == step.index)
        }
    }
}
