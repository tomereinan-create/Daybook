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
                preAlertOffsets: [600],
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
                preAlertOffsets: [3600],
                nag: .off,
                escalates: false,
                snoozeAllowed: false,
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
                nag: .off,
                escalates: false,
                snoozeAllowed: false,
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
                snoozeAllowed: false,
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
                snoozeAllowed: false,
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
            s.trigger = .countdown(minutes: 45)
            s.visibility = Visibility(leadTime: 0, surfaces: .all)
            s.alerting = Alerting(
                intensity: .timeSensitive,
                preAlertOffsets: [],
                nag: .off,
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
                snoozeAllowed: false,
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
                nag: .off,
                escalates: false,
                snoozeAllowed: false,
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

    /// Which setting groups the editor shows before the user opens a drawer.
    ///
    /// Three of these are on every preset: when it happens, where it shows,
    /// and whether it makes a sound. Those are the questions people actually
    /// ask when they write something down, and burying them under Advanced
    /// made the basics look like there was nothing to decide. What varies is
    /// the one field that gives the preset its character — the quota, the
    /// steps, the duration.
    var prominentFields: Set<SettingField> {
        let basics: Set<SettingField> = [.surfaces, .intensity]
        return switch self {
        case .event: basics.union([.trigger])
        case .task: basics.union([.trigger])
        case .deadlineTask: basics.union([.trigger])
        case .recurringTask: basics.union([.trigger, .recurrence])
        case .locationReminder: basics.union([.location])
        case .flexibleHabit: basics.union([.quota])
        case .timeBlock: basics.union([.trigger, .window])
        case .relativeTimer: basics.union([.relativeDuration])
        case .routine: basics.union([.trigger, .recurrence, .steps])
        case .waitingFor: basics.union([.followUpInterval])
        case .someday: basics
        case .wakeUp: basics.union([.trigger, .recurrence])
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
    case timerStart
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

/// The drawers the editor files a preset's remaining settings into.
///
/// One "Advanced" list of eighteen rows reads as a wall; four named drawers,
/// each shut until asked for, read as a place to look something up. Used only
/// by the UI.
nonisolated enum SettingGroup: String, Sendable, Hashable, CaseIterable, Identifiable {
    case timing
    case alerts
    case display
    case extras

    var id: String { rawValue }
}

nonisolated extension SettingField {
    var group: SettingGroup {
        switch self {
        case .trigger, .recurrence, .quota, .location, .relativeDuration, .timerStart,
             .window, .onMissed:
            .timing
        case .intensity, .preAlerts, .nag, .escalation, .snooze, .quietHours:
            .alerts
        case .leadTime, .surfaces:
            .display
        case .priority, .steps, .followUpInterval:
            .extras
        }
    }
}
