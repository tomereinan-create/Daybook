import Foundation

/// Why a notification exists. The scheduler turns this into localized copy;
/// the engine stays free of user-facing text.
enum AlertRole: String, Sendable, Hashable, CaseIterable {
    case preAlert
    case primary
    case nag
    /// A flexible habit that has fallen behind its pace.
    case quotaNudge
    /// A waiting-for item that has had no update.
    case followUp
}

struct PlannedNotification: Sendable, Hashable, Identifiable {
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

    var allowsSnooze: Bool { snoozeMinutes != nil }
}

struct PlannedAlarm: Sendable, Hashable, Identifiable {
    let id: String
    let key: OccurrenceKey
    let title: String
    let fireDate: Date
    let snoozeMinutes: Int?
}

struct NotificationPlan: Sendable {
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
struct NotificationPlanner: Sendable {
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
            alarms: alarms.sorted { $0.fireDate < $1.fireDate },
            droppedCount: max(dropped, 0),
            window: window
        )
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
        let alerting = occurrence.item.settings.alerting
        return [
            PlannedAlarm(
                id: Self.identifier(occurrence.key, role: .primary, sequence: 0),
                key: occurrence.key,
                title: occurrence.displayTitle,
                fireDate: trigger,
                snoozeMinutes: alerting.snoozeAllowed ? alerting.snoozeMinutes : nil
            )
        ]
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
                id: Self.identifier(occurrence.key, role: role, sequence: sequence),
                key: occurrence.key,
                title: occurrence.displayTitle,
                fireDate: fire,
                intensity: intensity,
                role: role,
                sequence: sequence,
                isMandatory: occurrence.item.settings.priority == .mandatory,
                snoozeMinutes: alerting.snoozeAllowed ? alerting.snoozeMinutes : nil
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

    /// Stable across reschedules, so a pending request can be found and
    /// cancelled the instant its occurrence is completed from any surface.
    static func identifier(_ key: OccurrenceKey, role: AlertRole, sequence: Int) -> String {
        "\(prefix(for: key))\(role.rawValue).\(sequence)"
    }

    /// Every request for one occurrence starts with this, which is how
    /// completion cancels a whole family of pending nags in one call.
    static func prefix(for key: OccurrenceKey) -> String {
        "\(key.itemID.uuidString)|\(Int(key.slot.timeIntervalSince1970))|"
    }

    static func itemPrefix(for itemID: UUID) -> String {
        "\(itemID.uuidString)|"
    }
}
