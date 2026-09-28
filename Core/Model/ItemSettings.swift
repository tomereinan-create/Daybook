import Foundation

/// Everything that decides how an item behaves. The engine reads only this;
/// it never branches on the preset an item was created from.
struct ItemSettings: Codable, Sendable, Hashable {
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
