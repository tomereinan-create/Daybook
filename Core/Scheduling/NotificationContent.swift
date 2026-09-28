import Foundation

/// Everything a notification needs to be posted, as a `Sendable` value.
///
/// The engine produces roles and instants; this turns them into words. Keeping
/// it a plain struct means the widget process, the tests and the app all build
/// the same copy, and nothing has to hand a `UNNotificationRequest` across an
/// isolation boundary.
struct NotificationContent: Sendable, Hashable {
    var title: String
    var body: String
    var categoryIdentifier: String
    var interruptionLevel: NotificationInterruptionLevel
    var isSilent: Bool
    /// Carried through so an action handler can find the occurrence again.
    var itemID: UUID
    var slot: Date
    var snoozeMinutes: Int?

    var userInfo: [String: String] {
        var info = [
            NotificationUserInfoKey.itemID: itemID.uuidString,
            NotificationUserInfoKey.slot: String(Int(slot.timeIntervalSince1970))
        ]
        if let snoozeMinutes {
            info[NotificationUserInfoKey.snoozeMinutes] = String(snoozeMinutes)
        }
        return info
    }
}

enum NotificationUserInfoKey {
    static let itemID = "itemID"
    static let slot = "slot"
    static let snoozeMinutes = "snoozeMinutes"
}

/// Mirrors `UNNotificationInterruptionLevel` without importing it, so this file
/// stays testable and the mapping lives in one obvious place.
enum NotificationInterruptionLevel: String, Sendable, Hashable, CaseIterable {
    case passive
    case active
    case timeSensitive
}

/// Turns a planned alert into words. The only place in the project that knows
/// what a nag should say.
struct NotificationContentBuilder: Sendable {
    init() {}

    func content(for notification: PlannedNotification) -> NotificationContent {
        NotificationContent(
            title: notification.title,
            body: body(for: notification),
            categoryIdentifier: category(for: notification).rawValue,
            interruptionLevel: level(for: notification.intensity),
            isSilent: notification.intensity == .silent,
            itemID: notification.key.itemID,
            slot: notification.key.slot,
            snoozeMinutes: notification.snoozeMinutes
        )
    }

    func body(for notification: PlannedNotification) -> String {
        switch notification.role {
        case .preAlert:
            guard let lead = notification.leadTime, lead > 0 else {
                return String(localized: "alert.body.primary")
            }
            return String(localized: "alert.body.preAlert \(Self.relative(lead))")
        case .primary:
            return String(localized: "alert.body.primary")
        case .nag:
            // The user has seen this one already, so say which time this is.
            return String(localized: "alert.body.nag \(notification.sequence + 2)")
        case .quotaNudge:
            return String(localized: "alert.body.quotaNudge")
        case .followUp:
            return String(localized: "alert.body.followUp")
        }
    }

    /// "1 hour", "10 minutes" — localized and pluralised by Foundation.
    static func relative(_ seconds: TimeInterval) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: seconds >= 3600 ? [.hours, .minutes] : [.minutes],
            width: .wide,
            zeroValueUnits: .hide
        )
        return Duration.seconds(max(seconds, 60)).formatted(style)
    }

    func category(for notification: PlannedNotification) -> NotificationCategory {
        notification.allowsSnooze ? .actionableWithSnooze : .actionable
    }

    func level(for intensity: Intensity) -> NotificationInterruptionLevel {
        switch intensity {
        case .none, .silent: .passive
        case .standard: .active
        case .timeSensitive, .alarm: .timeSensitive
        }
    }
}

/// The categories registered at launch. Their identifiers are stable strings
/// because iOS matches delivered notifications against them by name.
enum NotificationCategory: String, Sendable, CaseIterable {
    case actionable = "daybook.actionable"
    case actionableWithSnooze = "daybook.actionable.snooze"
}

enum NotificationAction: String, Sendable, CaseIterable {
    case done = "daybook.action.done"
    case snooze = "daybook.action.snooze"
}
