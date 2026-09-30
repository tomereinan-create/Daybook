import Foundation
import Testing
@testable import Daybook

@Suite("Saying you did not do it")
struct NotDoneTests {
    let calendar = Fixture.calendar()
    let resolver = StateResolver(calendar: Fixture.calendar())

    private var anchor: Date { Fixture.date(2026, 3, 1, 0, 0, calendar: calendar) }

    private func occurrence(of item: ItemSnapshot, on day: Date) -> GeneratedOccurrence {
        let range = calendar.startOfDay(for: day)..<calendar.startOfNextDay(after: day)
        guard let first = OccurrenceGenerator(calendar: calendar)
            .occurrences(for: item, in: range).first
        else { fatalError("expected an occurrence on \(day)") }
        return first
    }

    @Test("An undated task marked not done leaves the list")
    func undatedTaskCanBeDismissed() {
        let item = Fixture.item(settings: .default, createdAt: anchor)
        let generated = occurrence(of: item, on: anchor)
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)

        // Without an explicit answer it sits there forever, which is the point
        // of a task.
        let open = resolver.resolve(item: item, generated: generated, record: nil, now: now)
        #expect(open.state == .visible)

        let dismissed = resolver.resolve(
            item: item,
            generated: generated,
            record: OccurrenceStateRecord(key: generated.key, missedAt: now),
            now: now
        )
        #expect(dismissed.state == .missed)
        #expect(!dismissed.state.isOutstanding)
        #expect(!dismissed.state.appearsOnLiveSurfaces)
    }

    @Test("Not done beats the clock, even inside the window")
    func notDoneOutranksTiming() {
        let item = Fixture.dailyItem(
            at: TimeOfDay(hour: 9, minute: 0),
            from: anchor,
            endCondition: .windowEnds(3600)
        )
        let generated = occurrence(of: item, on: Fixture.date(2026, 3, 10, 0, 0, calendar: calendar))
        let during = Fixture.date(2026, 3, 10, 9, 20, calendar: calendar)

        // Mid-window it would otherwise be active.
        #expect(resolver.resolve(item: item, generated: generated, record: nil, now: during).state == .active)

        let dismissed = resolver.resolve(
            item: item,
            generated: generated,
            record: OccurrenceStateRecord(key: generated.key, missedAt: during),
            now: during
        )
        #expect(dismissed.state == .missed)
    }

    @Test("Done still beats not done, so an undo cannot leave both set")
    func doneOutranksNotDone() {
        let item = Fixture.item(settings: .default, createdAt: anchor)
        let generated = occurrence(of: item, on: anchor)
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)

        let both = OccurrenceStateRecord(key: generated.key, completedAt: now, missedAt: now)
        #expect(resolver.resolve(item: item, generated: generated, record: both, now: now).state == .done)
    }

    @Test("Undo clears both answers and the row comes back")
    func reopenClearsEverything() {
        let service = CompletionService()
        let item = Fixture.item(settings: .default, createdAt: anchor)
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let key = OccurrenceKey(itemID: item.id, slot: anchor)

        let dismissed = service.markMissed(OccurrenceStateRecord(key: key), now: now)
        #expect(dismissed.missedAt != nil)

        let reopened = service.reopen(dismissed, item: item)
        #expect(reopened.missedAt == nil)
        #expect(reopened.completedAt == nil)

        let generated = occurrence(of: item, on: anchor)
        #expect(resolver.resolve(item: item, generated: generated, record: reopened, now: now).state == .visible)
    }
}

@Suite("Backup and restore")
struct BackupTests {
    let calendar = Fixture.calendar()

    @Test("A backup round-trips through JSON unchanged")
    func roundTrips() throws {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        var settings = PresetKind.recurringTask.defaultSettings(reference: now, calendar: calendar)
        settings.steps = [Step(title: "Kettle"), Step(title: "Pills")]
        settings.recurrence = Recurrence(
            frequency: .weekdays([.monday, .wednesday]),
            end: .afterOccurrences(12),
            anchorDate: now
        )

        let payload = DataExport(
            exportedAt: now,
            items: [
                DataExport.ExportedItem(
                    id: UUID(),
                    title: "Physio exercises",
                    notes: "Three sets",
                    preset: .recurringTask,
                    settings: settings,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            records: [
                DataExport.ExportedRecord(
                    itemID: UUID(),
                    slot: now,
                    completedAt: now,
                    missedAt: nil,
                    snoozedUntil: nil,
                    startedAt: nil,
                    currentStepIndex: 1,
                    nagsFired: 0,
                    completionCount: 2
                )
            ]
        )

        let data = try DataExport.encoder().encode(payload)
        let restored = try DataTransfer.read(data)

        #expect(restored.items.count == 1)
        #expect(restored.items[0].title == "Physio exercises")
        // The settings are the part worth checking: a recurrence and a step
        // list that survive a round trip mean nothing was lost.
        #expect(restored.items[0].settings == settings)
        #expect(restored.records[0].currentStepIndex == 1)
        #expect(restored.records[0].completionCount == 2)
    }

    @Test("Rubbish is refused rather than half-imported")
    func rejectsNonsense() {
        #expect(throws: (any Error).self) {
            try DataTransfer.read(Data("not a backup".utf8))
        }
        #expect(throws: (any Error).self) {
            try DataTransfer.read(Data("{\"version\":99,\"exportedAt\":\"2026-03-10T09:00:00Z\",\"items\":[],\"records\":[]}".utf8))
        }
    }

    @Test("A backup is readable by a person, not just a parser")
    func isHumanReadable() throws {
        let now = Fixture.date(2026, 3, 10, 9, 0, calendar: calendar)
        let payload = DataExport(exportedAt: now, items: [], records: [])
        let text = try String(decoding: DataExport.encoder().encode(payload), as: UTF8.self)

        // ISO dates and pretty printing, so the file still makes sense if
        // Daybook is not around to open it.
        #expect(text.contains("2026-03-10T"))
        #expect(text.contains("\n"))
    }
}

@Suite("Presets are quiet until told otherwise")
struct PresetQuietnessTests {
    let calendar = Fixture.calendar()
    private var now: Date { Fixture.date(2026, 3, 10, 9, 30, calendar: calendar) }

    @Test("No preset nags or escalates by default", arguments: PresetKind.allCases)
    func nothingIsOnByDefault(preset: PresetKind) {
        let settings = preset.defaultSettings(reference: now, calendar: calendar)
        // These live under Advanced, and a setting that is both hidden and on
        // is the worst of both.
        #expect(!settings.alerting.nag.isEnabled)
        #expect(!settings.alerting.escalates)
    }

    @Test("At most one reminder before the time, and snooze is opt-in",
          arguments: PresetKind.allCases)
    func alertsArriveSparingly(preset: PresetKind) {
        let settings = preset.defaultSettings(reference: now, calendar: calendar)
        #expect(settings.alerting.preAlertOffsets.count <= 1)
        // A timer and an alarm are the two things whose whole point is going
        // off, so "not yet" has to be on the screen when they do. Everything
        // else starts without it.
        if preset != .relativeTimer, preset != .wakeUp {
            #expect(!settings.alerting.snoozeAllowed)
        }
    }

    @Test("Every preset shows when, where and how loud up front",
          arguments: PresetKind.allCases)
    func basicsAreAlwaysVisible(preset: PresetKind) {
        let prominent = preset.prominentFields
        #expect(prominent.contains(.surfaces))
        #expect(prominent.contains(.intensity))
        // And, for anything meant to appear somewhere, something that says
        // when: a time, a place, a quota or a duration. Someday and
        // waiting-for are hidden on purpose and answer that question with
        // "not yet", so they are the ones exempt.
        let settings = preset.defaultSettings(reference: now, calendar: calendar)
        let whens: Set<SettingField> = [.trigger, .location, .quota, .relativeDuration]
        if !settings.visibility.surfaces.isEmpty {
            #expect(!prominent.isDisjoint(with: whens))
        }
    }

    @Test("Nothing falls out of the drawers")
    func everyFieldIsFiledSomewhere() {
        // Each field belongs to exactly one group, so a preset's advanced
        // fields always add up to the fields it does not show up front.
        for preset in PresetKind.allCases {
            let advanced = SettingField.allCases.filter { !preset.prominentFields.contains($0) }
            let filed = SettingGroup.allCases.flatMap { group in
                advanced.filter { $0.group == group }
            }
            #expect(Set(filed) == Set(advanced))
            #expect(filed.count == advanced.count)
        }
    }

    @Test("A timer starts itself; a manual countdown waits")
    func timerStartsOnItsOwn() {
        let timer = PresetKind.relativeTimer.defaultSettings(reference: now, calendar: calendar)
        #expect(timer.trigger.runsUnattended)
        #expect(!Trigger.minutesAfterStart(20).runsUnattended)
        // The flag means nothing for anything that is not a countdown.
        #expect(!Trigger.at(now).runsUnattended)
    }

    // The catalog is main-actor isolated, so it is read inside the body
    // rather than passed as `arguments:`, which is evaluated outside it.
    @Test("Everything the create flow offers can reach both surfaces")
    func offeredPresetsReachTheSurfaces() {
        // The app is where things are written down; the lock screen and the
        // widget are where they are meant to be seen. A preset that reaches
        // neither looks like a broken surface rather than a choice.
        for preset in PresetCatalog.available {
            let settings = preset.defaultSettings(reference: now, calendar: calendar)
            #expect(settings.visibility.surfaces.contains(.liveActivity))
            #expect(settings.visibility.surfaces.contains(.homeWidget))
        }
    }

    @Test("The five kinds the create flow offers")
    func offeredPresets() {
        #expect(PresetCatalog.available == [.task, .event, .recurringTask, .routine, .relativeTimer])
    }
}

@Suite("The setup notice names one blocker at a time")
struct SetupNoticeTests {
    private var healthy: Diagnostics {
        Diagnostics(
            notifications: .authorized,
            pendingWithSystem: 3,
            hasSharedContainer: true,
            hasWidgetExtension: true,
            liveActivitiesEnabled: true,
            liveActivityRunning: true,
            onLockScreen: 2,
            onHomeWidget: 2,
            itemsToday: 2
        )
    }

    @Test("Nothing to say when everything works")
    func silentWhenHealthy() {
        #expect(SetupNotice.first(from: healthy) == nil)
    }

    @Test("Never being asked outranks everything else")
    func permissionComesFirst() {
        // Deliberately broken in every way at once. Explaining the lock-screen
        // card to somebody who has not been asked about notifications yet is
        // answering the second question first.
        var d = healthy
        d.notifications = .notDetermined
        d.hasWidgetExtension = false
        d.liveActivitiesEnabled = false
        d.hasSharedContainer = false
        d.onLockScreen = 0
        d.onHomeWidget = 0
        #expect(SetupNotice.first(from: d) == .notificationsNeverAsked)
        #expect(SetupNotice.first(from: d)?.action == .ask)
    }

    @Test("A refusal sends them to iOS, because the app cannot ask twice")
    func deniedGoesToSystemSettings() {
        var d = healthy
        d.notifications = .denied
        #expect(SetupNotice.first(from: d) == .notificationsDenied)
        #expect(SetupNotice.first(from: d)?.action == .openSystemSettings)
    }

    @Test("A missing extension outranks everything it makes impossible")
    func theExtensionComesBeforeItsSymptoms() {
        // With no extension there is no widget to add and no card to draw, so
        // saying "Live Activities are off" would send them to a switch that
        // could not help.
        var d = healthy
        d.hasWidgetExtension = false
        d.liveActivitiesEnabled = false
        d.hasSharedContainer = false
        #expect(SetupNotice.first(from: d) == .widgetExtensionMissing)
        #expect(SetupNotice.first(from: d)?.action == nil)

        // But a refusal still comes first: that one the app can talk about.
        d.notifications = .denied
        #expect(SetupNotice.first(from: d) == .notificationsDenied)
    }

    @Test("Then the card, then the container, then the items")
    func theRestFollowInOrder() {
        var d = healthy
        d.liveActivitiesEnabled = false
        d.hasSharedContainer = false
        #expect(SetupNotice.first(from: d) == .liveActivitiesOff)

        d.liveActivitiesEnabled = true
        #expect(SetupNotice.first(from: d) == .noSharedContainer)

        d.hasSharedContainer = true
        d.onLockScreen = 0
        d.onHomeWidget = 0
        #expect(SetupNotice.first(from: d) == .nothingOnSurfaces)
    }

    @Test("An empty day is not a misconfigured one")
    func noItemsIsNotAProblem() {
        var d = healthy
        d.onLockScreen = 0
        d.onHomeWidget = 0
        d.itemsToday = 0
        #expect(SetupNotice.first(from: d) == nil)
    }

    @Test("Only what cannot be acted on here can be put away")
    func onlyUnactionableNoticesDismiss() {
        for notice in SetupNotice.allCases {
            #expect(notice.isDismissible == (notice.action == nil))
        }
    }
}

@Suite("Choosing which app group to open")
struct AppGroupResolutionTests {
    private let declared = "group.com.tomereinan.daybook"

    @Test("With nothing granted, the compiled-in name stands")
    func noSignatureKeepsTheDeclaredName() {
        // A simulator build is signed with nothing at all. An empty list is
        // not evidence that the name is wrong.
        #expect(AppGroup.resolve(declared: declared, granted: []) == declared)
    }

    @Test("A signature that grants the name it was asked for changes nothing")
    func grantedDeclaredNameWins() {
        #expect(
            AppGroup.resolve(declared: declared, granted: ["group.other", declared]) == declared
        )
    }

    @Test("A substituted name is used instead of one that opens nothing")
    func substitutedNameIsAdopted() {
        // What a re-signing tool does on a free account: it cannot register
        // the name in the project, so it grants one of its own.
        let substitute = "group.ABCDE12345.com.tomereinan.daybook"
        #expect(AppGroup.resolve(declared: declared, granted: [substitute]) == substitute)
    }

    @Test("Several granted groups resolve the same way every time")
    func theChoiceIsDeterministic() {
        // The app and the extension resolve this separately. If they disagreed
        // they would open different containers, which is the bug this is meant
        // to fix rather than cause.
        let groups = ["group.zzz.daybook", "group.aaa.daybook", "group.mmm.daybook"]
        let first = AppGroup.resolve(declared: declared, granted: groups)
        #expect(first == "group.aaa.daybook")
        #expect(AppGroup.resolve(declared: declared, granted: groups.reversed()) == first)
        #expect(AppGroup.resolve(declared: declared, granted: groups.shuffled()) == first)
    }
}
