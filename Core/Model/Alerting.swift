import Foundation

nonisolated enum Intensity: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    /// Appears on surfaces but never posts a notification.
    case none = 0
    case silent = 1
    case standard = 2
    case timeSensitive = 3
    /// Routed to AlarmKit rather than UserNotifications.
    case alarm = 4

    static func < (lhs: Intensity, rhs: Intensity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// One rung up, saturating at `.alarm`.
    var escalated: Intensity {
        Intensity(rawValue: min(rawValue + 1, Intensity.alarm.rawValue)) ?? self
    }
}

nonisolated struct Nag: Codable, Sendable, Hashable {
    var isEnabled: Bool
    var intervalMinutes: Int
    var maxRepeats: Int

    static let off = Nag(isEnabled: false, intervalMinutes: 10, maxRepeats: 3)

    static func every(_ minutes: Int, upTo repeats: Int) -> Nag {
        Nag(isEnabled: true, intervalMinutes: minutes, maxRepeats: repeats)
    }
}

nonisolated struct Alerting: Codable, Sendable, Hashable {
    var intensity: Intensity
    /// Seconds *before* the trigger. Always positive.
    var preAlertOffsets: [TimeInterval]
    var nag: Nag
    /// When true, each nag fires one intensity rung higher than the last.
    var escalates: Bool
    var snoozeAllowed: Bool
    var snoozeMinutes: Int

    static let silentDisplayOnly = Alerting(
        intensity: .none,
        preAlertOffsets: [],
        nag: .off,
        escalates: false,
        snoozeAllowed: false,
        snoozeMinutes: 10
    )

    static let standard = Alerting(
        intensity: .standard,
        preAlertOffsets: [],
        nag: .off,
        escalates: false,
        snoozeAllowed: true,
        snoozeMinutes: 10
    )
}
