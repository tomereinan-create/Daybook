import Foundation

/// The twelve starting points offered in the create flow.
///
/// A preset is *only* a bag of defaults. Once an item is created the preset is
/// kept for display and to decide which fields the editor shows first, but no
/// engine decision is ever made from it.
nonisolated enum PresetKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case event
    case task
    case deadlineTask
    case recurringTask
    case locationReminder
    case flexibleHabit
    case timeBlock
    case relativeTimer
    case routine
    case waitingFor
    case someday
    case wakeUp

    var id: String { rawValue }
}

nonisolated extension PresetKind {
    /// The settings a freshly created item of this kind starts with.
    /// `reference` is "now": it anchors the recurrence and places a first
    /// sensible trigger date.
    func defaultSettings(reference: Date, calendar: Calendar) -> ItemSettings {
        var s = ItemSettings.default
        let anchor = calendar.startOfDay(for: reference)
        s.recurrence.anchorDate = anchor

        switch self {
        case .event:
            s.trigger = .at(calendar.nextHour(after: reference))
            s.recurrence = Recurrence(frequency: .once, end: .never, anchorDate: anchor)
            s.visibility = Visibility(leadTime: 4 * 3600, surfaces: .all)
            s.alerting = Alerting(
                intensity: .standard,
                preAlertOffsets: [3600, 600],
                nag: .off,
                escalates: false,
                snoozeAllowed: false,
                snoozeMinutes: 10
            )
            s.dismissal = .atEventStart

        case .task:
            s.trigger = .none
            s.visibility = Visibility(leadTime: 0, surfaces: .homeWidget)
            s.alerting = .silentDisplayOnly
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)

        case .deadlineTask:
            s.trigger = .at(calendar.endOfDay(for: reference))
            s.visibility = Visibility(leadTime: 24 * 3600, surfaces: .all)
            s.alerting = Alerting(
                intensity: .standard,
                preAlertOffsets: [24 * 3600, 4 * 3600, 3600],
                nag: .every(30, upTo: 4),
                escalates: true,
                snoozeAllowed: true,
                snoozeMinutes: 15
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)

        case .recurringTask:
            s.trigger = .daily(at: TimeOfDay(hour: 8, minute: 0))
            s.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
            s.visibility = Visibility(leadTime: 1800, surfaces: .all)
            s.alerting = Alerting(
                intensity: .standard,
                preAlertOffsets: [],
                nag: .every(15, upTo: 3),
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 10
            )
            s.dismissal = Dismissal(endCondition: .windowEnds(3 * 3600), onMissed: .logMissed)

        case .locationReminder:
            s.trigger = Trigger(kind: .location, location: nil)
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .timeSensitive,
                preAlertOffsets: [],
                nag: .off,
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 30
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)

        case .flexibleHabit:
            s.trigger = .none
            s.recurrence = Recurrence(
                frequency: .quota(count: 3, period: .week),
                end: .never,
                anchorDate: anchor
            )
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .silent,
                preAlertOffsets: [],
                nag: .off,
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 60
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .logMissed)

        case .timeBlock:
            s.trigger = .at(calendar.nextHour(after: reference))
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .standard,
                preAlertOffsets: [],
                nag: .off,
                escalates: false,
                snoozeAllowed: false,
                snoozeMinutes: 5
            )
            s.dismissal = Dismissal(endCondition: .windowEnds(3600), onMissed: .logMissed)

        case .relativeTimer:
            s.trigger = .minutesAfterStart(45)
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .timeSensitive,
                preAlertOffsets: [],
                nag: .every(5, upTo: 3),
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 5
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)

        case .routine:
            s.trigger = .daily(at: TimeOfDay(hour: 7, minute: 0))
            s.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
            s.visibility = Visibility(leadTime: 900, surfaces: .all)
            s.alerting = Alerting(
                intensity: .standard,
                preAlertOffsets: [],
                nag: .off,
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 10
            )
            s.dismissal = Dismissal(endCondition: .windowEnds(2 * 3600), onMissed: .logMissed)
            s.steps = []

        case .waitingFor:
            s.trigger = .none
            s.visibility = .hidden
            s.alerting = Alerting(
                intensity: .silent,
                preAlertOffsets: [],
                nag: .every(3 * 24 * 60, upTo: 5),
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 24 * 60
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)

        case .someday:
            s.trigger = .none
            s.visibility = .hidden
            s.alerting = .silentDisplayOnly
            s.dismissal = Dismissal(endCondition: .manualOnly, onMissed: .becomeOpenTask)

        case .wakeUp:
            s.trigger = .daily(at: TimeOfDay(hour: 7, minute: 0))
            s.recurrence = Recurrence(
                frequency: .weekdays(Set(Weekday.allCases)),
                end: .never,
                anchorDate: anchor
            )
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .alarm,
                preAlertOffsets: [],
                nag: .off,
                escalates: false,
                snoozeAllowed: true,
                snoozeMinutes: 9
            )
            s.dismissal = Dismissal(endCondition: .markedDone, onMissed: .logMissed)
            s.quietHours = .override
            s.priority = .mandatory
        }

        return s
    }

    /// Which setting groups the editor shows before the user opens "Advanced".
    var prominentFields: Set<SettingField> {
        switch self {
        case .event: [.trigger, .preAlerts]
        case .task: [.priority]
        case .deadlineTask: [.trigger, .preAlerts, .escalation]
        case .recurringTask: [.trigger, .recurrence, .window]
        case .locationReminder: [.location]
        case .flexibleHabit: [.quota]
        case .timeBlock: [.trigger, .window]
        case .relativeTimer: [.relativeDuration]
        case .routine: [.trigger, .recurrence, .steps]
        case .waitingFor: [.followUpInterval]
        case .someday: [.priority]
        case .wakeUp: [.trigger, .recurrence, .snooze]
        }
    }
}

/// The editor's units of disclosure. Used only by the UI.
nonisolated enum SettingField: String, Sendable, Hashable, CaseIterable {
    case trigger
    case recurrence
    case quota
    case location
    case relativeDuration
    case leadTime
    case surfaces
    case intensity
    case preAlerts
    case nag
    case escalation
    case snooze
    case window
    case onMissed
    case priority
    case quietHours
    case steps
    case followUpInterval
}
