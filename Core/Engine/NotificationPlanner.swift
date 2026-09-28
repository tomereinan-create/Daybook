import CryptoKit
import Foundation

/// Why a notification exists. The scheduler turns this into localized copy;
/// the engine stays free of user-facing text.
nonisolated enum AlertRole: String, Sendable, Hashable, CaseIterable {
    case preAlert
    case primary
    case nag
    /// A flexible habit that has fallen behind its pace.
    case quotaNudge
    /// A waiting-for item that has had no update.
    case followUp
}

nonisolated struct PlannedNotification: Sendable, Hashable, Identifiable {
    let id: String
    let key: OccurrenceKey
    let title: String
    let fireDate: Date
    let intensity: Intensity
    let role: AlertRole
    /// Which nag or pre-alert this is, zero-based. Always 0 for `.primary`.
    let sequence: Int
    let isMandatory: Bool
    let snoozeMinutes: Int?
    /// When the thing itself happens. A pre-alert fires before this; a nag
    /// after it. `nil` for alerts with no calendar-bound trigger.
    let triggerDate: Date?

    var allowsSnooze: Bool { snoozeMinutes != nil }

    /// How long before the thing itself this alert lands. Negative once the
    /// trigger has passed, which is the nag case.
    var leadTime: TimeInterval? {
        triggerDate.map { $0.timeIntervalSince(fireDate) }
    }
}

nonisolated struct PlannedAlarm: Sendable, Hashable, Identifiable {
    let id: String
    /// AlarmKit identifies alarms by `UUID`, and it has to be the same one
    /// every time we reschedule or we would stack duplicates. Derived from the
    /// item or the occurrence, never random.
    let alarmID: UUID
    let key: OccurrenceKey
    let title: String
    let fireDate: Date
    let snoozeMinutes: Int?
    /// Non-empty when AlarmKit can own the recurrence itself. We then schedule
    /// one repeating alarm for the item instead of one per day, which is both
    /// what the system expects and what keeps a 07:00 wake-up at 07:00 through
    /// a clock change.
    let weekdays: Set<Weekday>

    var repeatsWeekly: Bool { !weekdays.isEmpty }
}

nonisolated struct NotificationPlan: Sendable {
    /// At most `configuration.notificationBudget` entries, ascending by time.
    let notifications: [PlannedNotification]
    let alarms: [PlannedAlarm]
    /// How many candidates the budget forced out, for the diagnostics screen.
    let droppedCount: Int
    let window: DateInterval

    static let empty = NotificationPlan(
        notifications: [],
        alarms: [],
        droppedCount: 0,
        window: DateInterval(start: .distantPast, duration: 0)
    )
}

/// Builds the rolling set of notifications and alarms for the next window.
///
/// The 64-request iOS cap is the constraint that shapes this whole type: the
/// planner always produces a *candidate* list first, then spends the budget on
/// the things that matter most, primary alerts before repeat nags.
nonisolated struct NotificationPlanner: Sendable {
    var calendar: Calendar
    var configuration: EngineConfiguration
    var quietHours: QuietHours

    init(
        calendar: Calendar,
        configuration: EngineConfiguration = .default,
        quietHours: QuietHours = .default
    ) {
        self.calendar = calendar
        self.configuration = configuration
        self.quietHours = quietHours
    }

    func plan(for resolved: [ResolvedOccurrence], now: Date) -> NotificationPlan {
        let window = DateInterval(start: now, duration: configuration.schedulingWindow)
        var primaries: [PlannedNotification] = []
        var repeats: [PlannedNotification] = []
        var alarms: [PlannedAlarm] = []

        for occurrence in resolved {
            guard occurrence.state.isOutstanding else { continue }
            let alerting = occurrence.item.settings.alerting

            if alerting.intensity == .alarm {
                alarms.append(contentsOf: alarmCandidates(for: occurrence, window: window))
                continue
            }
            guard alerting.intensity > .none else { continue }

            let candidates = candidates(for: occurrence, window: window)
            for candidate in candidates {
                switch candidate.role {
                case .preAlert, .primary:
                    primaries.append(candidate)
                case .nag, .quotaNudge, .followUp:
                    repeats.append(candidate)
                }
            }
        }

        let budget = max(configuration.notificationBudget, 0)
        var chosen = Array(primaries.sorted(by: Self.isHigherValue).prefix(budget))
        if chosen.count < budget {
            chosen += repeats.sorted(by: Self.isHigherValue).prefix(budget - chosen.count)
        }
        let dropped = (primaries.count + repeats.count) - chosen.count

        return NotificationPlan(
            notifications: chosen.sorted { $0.fireDate < $1.fireDate },
            alarms: Self.collapseRepeats(alarms),
            droppedCount: max(dropped, 0),
            window: window
        )
    }

    /// A daily wake-up has an occurrence on every day of the window, but
    /// AlarmKit wants one repeating alarm, not three. Keep the earliest of each
    /// identifier and drop the rest.
    static func collapseRepeats(_ alarms: [PlannedAlarm]) -> [PlannedAlarm] {
        var earliest: [UUID: PlannedAlarm] = [:]
        for alarm in alarms {
            if let existing = earliest[alarm.alarmID], existing.fireDate <= alarm.fireDate { continue }
            earliest[alarm.alarmID] = alarm
        }
        return earliest.values.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Candidates

    func candidates(for occurrence: ResolvedOccurrence, window: DateInterval) -> [PlannedNotification] {
        let item = occurrence.item
        let alerting = item.settings.alerting
        var result: [PlannedNotification] = []

        if let trigger = occurrence.effectiveTrigger {
            for (index, offset) in alerting.preAlertOffsets.sorted(by: >).enumerated() {
                let fire = trigger.addingTimeInterval(-abs(offset))
                append(
                    &result,
                    occurrence: occurrence,
                    fire: fire,
                    role: .preAlert,
                    sequence: index,
                    intensity: alerting.intensity,
                    window: window
                )
            }

            append(
                &result,
                occurrence: occurrence,
                fire: trigger,
                role: .primary,
                sequence: 0,
                intensity: alerting.intensity,
                window: window
            )

            if alerting.nag.isEnabled {
                result += nagCandidates(for: occurrence, from: trigger, role: .nag, window: window)
            }
        } else if let quota = occurrence.quotaProgress {
            if quota.isBehindPace, let fire = quotaNudgeDate(after: window.start) {
                append(
                    &result,
                    occurrence: occurrence,
                    fire: fire,
                    role: .quotaNudge,
                    sequence: 0,
                    intensity: alerting.intensity,
                    window: window
                )
            }
        } else if alerting.nag.isEnabled {
            // Undated items that still want chasing: waiting-for, mostly.
            let origin = occurrence.record.startedAt ?? occurrence.item.createdAt
            result += nagCandidates(for: occurrence, from: origin, role: .followUp, window: window)
        }

        return result
    }

    private func nagCandidates(
        for occurrence: ResolvedOccurrence,
        from origin: Date,
        role: AlertRole,
        window: DateInterval
    ) -> [PlannedNotification] {
        let alerting = occurrence.item.settings.alerting
        guard alerting.nag.maxRepeats > 0 else { return [] }
        let interval = TimeInterval(max(alerting.nag.intervalMinutes, 1)) * 60
        var result: [PlannedNotification] = []

        for step in 1...alerting.nag.maxRepeats {
            let fire = origin.addingTimeInterval(interval * Double(step))
            if let end = occurrence.windowEnd, fire >= end { break }
            if fire >= window.end { break }

            var intensity = alerting.intensity
            if alerting.escalates {
                for _ in 0..<step { intensity = intensity.escalated }
                // An escalating item never silently graduates into an alarm.
                intensity = min(intensity, .timeSensitive)
            }
            append(
                &result,
                occurrence: occurrence,
                fire: fire,
                role: role,
                sequence: step - 1,
                intensity: intensity,
                window: window
            )
        }
        return result
    }

    private func alarmCandidates(for occurrence: ResolvedOccurrence, window: DateInterval) -> [PlannedAlarm] {
        guard let trigger = occurrence.effectiveTrigger,
              trigger > window.start,
              trigger < window.end else { return [] }
        let item = occurrence.item
        let alerting = item.settings.alerting
        let weekdays = Self.weeklyDays(of: item.settings.recurrence.frequency)

        return [
            PlannedAlarm(
                id: Self.identifier(occurrence.key, role: .primary, sequence: 0, fireDate: trigger),
                // A repeating alarm belongs to the item, so its id must not
                // change from day to day; a one-off belongs to its occurrence.
                alarmID: weekdays.isEmpty ? Self.alarmID(for: occurrence.key) : item.id,
                key: occurrence.key,
                title: occurrence.displayTitle,
                fireDate: trigger,
                snoozeMinutes: alerting.snoozeAllowed ? alerting.snoozeMinutes : nil,
                weekdays: weekdays
            )
        ]
    }

    /// The days a frequency can hand to AlarmKit. Anything it cannot express
    /// weekly — every N days, a day of the month, a quota — returns empty and
    /// gets a fixed alarm per occurrence instead.
    static func weeklyDays(of frequency: Frequency) -> Set<Weekday> {
        switch frequency {
        case .daily: Set(Weekday.allCases)
        case .weekdays(let days): days
        case .once, .everyNDays, .dayOfMonth, .quota: []
        }
    }

    private func append(
        _ result: inout [PlannedNotification],
        occurrence: ResolvedOccurrence,
        fire: Date,
        role: AlertRole,
        sequence: Int,
        intensity: Intensity,
        window: DateInterval
    ) {
        guard fire > window.start, fire < window.end else { return }
        guard intensity > .none else { return }
        guard allowedByQuietHours(occurrence.item, at: fire) else { return }

        let alerting = occurrence.item.settings.alerting
        result.append(
            PlannedNotification(
                id: Self.identifier(occurrence.key, role: role, sequence: sequence, fireDate: fire),
                key: occurrence.key,
                title: occurrence.displayTitle,
                fireDate: fire,
                intensity: intensity,
                role: role,
                sequence: sequence,
                isMandatory: occurrence.item.settings.priority == .mandatory,
                snoozeMinutes: alerting.snoozeAllowed ? alerting.snoozeMinutes : nil,
                triggerDate: occurrence.effectiveTrigger
            )
        )
    }

    // MARK: - Policy

    func allowedByQuietHours(_ item: ItemSnapshot, at date: Date) -> Bool {
        guard item.settings.quietHours == .respect else { return true }
        return !quietHours.contains(calendar.timeOfDay(of: date))
    }

    /// Quota nudges land at a civilised hour rather than the moment the pace
    /// check flips.
    private func quotaNudgeDate(after now: Date) -> Date? {
        let time = TimeOfDay(hour: 18, minute: 0)
        guard let today = calendar.date(setting: time, on: now) else { return nil }
        if today > now { return today }
        return calendar.date(setting: time, on: calendar.startOfNextDay(after: now))
    }

    static func isHigherValue(_ a: PlannedNotification, _ b: PlannedNotification) -> Bool {
        if a.isMandatory != b.isMandatory { return a.isMandatory }
        if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
        return a.id < b.id
    }

    // MARK: - Identity

    /// Identifies one pending request.
    ///
    /// The fire time is part of the identifier on purpose. The scheduler
    /// reconciles by comparing identifiers, so an alert whose time moved has to
    /// look like a different request — otherwise the old one would survive at
    /// its old time and the new one would never be added. Everything before the
    /// `@` is stable, which is what makes prefix cancellation work.
    static func identifier(_ key: OccurrenceKey, role: AlertRole, sequence: Int, fireDate: Date) -> String {
        "\(prefix(for: key))\(role.rawValue).\(sequence)@\(Int(fireDate.timeIntervalSince1970))"
    }

    /// Every request for one occurrence starts with this, which is how
    /// completion cancels a whole family of pending nags in one call.
    static func prefix(for key: OccurrenceKey) -> String {
        "\(key.itemID.uuidString)|\(Int(key.slot.timeIntervalSince1970))|"
    }

    static func itemPrefix(for itemID: UUID) -> String {
        "\(itemID.uuidString)|"
    }

    /// A stable `UUID` for one occurrence, so rescheduling an alarm replaces it
    /// rather than stacking another copy beside it. Derived, never random: the
    /// same occurrence always produces the same identifier, on any launch and
    /// on any device.
    static func alarmID(for key: OccurrenceKey) -> UUID {
        let seed = "\(key.itemID.uuidString)|\(Int(key.slot.timeIntervalSince1970))"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
