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
    /// What completing this records besides the fact of it. Optional, like
    /// everything added after the first release: settings written by an
    /// earlier build carry no such key, and a missing key has to decode
    /// rather than throw the whole item away.
    var response: ResponseKind?
    /// Minutes to run after Done is pressed, for something that takes a known
    /// length of time. Two minutes of brushing; ten of stretching. Done starts
    /// the clock rather than stopping it.
    var holdMinutes: Int?

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
    /// What kind of answer completing this asks for, if any.
    var answerKind: ResponseKind { response ?? .none }

    /// How long Done runs for, or `nil` when Done simply finishes it.
    var holdDuration: Int? {
        guard let minutes = holdMinutes, minutes > 0 else { return nil }
        return minutes
    }

    /// False when nothing about this item could ever produce an alert: either
    /// it has no moment to alert at, or its alert is set to display only. A
    /// plain Task is both, on purpose — but that is worth saying out loud
    /// rather than leaving someone waiting for a notification that was never
    /// going to come.
    var canAlert: Bool {
        // A hold is announced whatever the alert setting says: the planner
        // raises a silent one to make sure of it, because a timer you cannot
        // hear is not a timer. So this is decided before the intensity.
        if holdDuration != nil { return true }
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
