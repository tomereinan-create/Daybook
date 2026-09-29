import Foundation

/// Everything that decides how an item behaves. The engine reads only this;
/// it never branches on the preset an item was created from.
nonisolated struct ItemSettings: Codable, Sendable, Hashable {
    var trigger: Trigger
    var recurrence: Recurrence
    var visibility: Visibility
    var alerting: Alerting
    var dismissal: Dismissal
    var priority: Priority
    var quietHours: QuietHoursPolicy
    var steps: [Step]

    static let `default` = ItemSettings(
        trigger: .none,
        recurrence: .once(),
        visibility: .standard,
        alerting: .silentDisplayOnly,
        dismissal: .untilDone,
        priority: .normal,
        quietHours: .respect,
        steps: []
    )
}

nonisolated extension ItemSettings {
    /// False when nothing about this item could ever produce an alert: either
    /// it has no moment to alert at, or its alert is set to display only. A
    /// plain Task is both, on purpose — but that is worth saying out loud
    /// rather than leaving someone waiting for a notification that was never
    /// going to come.
    var canAlert: Bool {
        guard alerting.intensity > .none else { return false }
        switch trigger.kind {
        case .time, .relative, .location:
            return true
        case .afterPrevious, .none:
            // Undated items can still chase you if they are set to.
            return alerting.nag.isEnabled || recurrence.frequency.isQuota
        }
    }
}
