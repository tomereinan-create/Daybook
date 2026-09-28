import Foundation
import UserNotifications

enum NotificationAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
    /// Allowed, but only into Notification Centre. No banners, no sound.
    case provisional

    var canPost: Bool { self == .authorized || self == .provisional }
}

/// The surface the scheduler needs from iOS.
///
/// A protocol so the reconciliation can be tested without a notification
/// centre, and so nothing has to pass a non-`Sendable` `UNNotificationRequest`
/// across an isolation boundary — the live implementation builds the request
/// from value types on the other side.
protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> Set<String>
    func add(_ notification: PlannedNotification, content: NotificationContent) async throws
    func removePending(identifiers: [String]) async
    func removeDelivered(identifiers: [String]) async
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func registerCategories() async
}

/// The real thing.
struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    init() {}

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }

    func add(_ notification: PlannedNotification, content: NotificationContent) async throws {
        let mutable = UNMutableNotificationContent()
        mutable.title = content.title
        mutable.body = content.body
        mutable.categoryIdentifier = content.categoryIdentifier
        mutable.userInfo = content.userInfo
        mutable.sound = content.isSilent ? nil : .default
        mutable.interruptionLevel = switch content.interruptionLevel {
        case .passive: .passive
        case .active: .active
        case .timeSensitive: .timeSensitive
        }
        // Grouping by item keeps a nagging item from filling the whole shade.
        mutable.threadIdentifier = content.itemID.uuidString
        if notification.isMandatory {
            mutable.relevanceScore = 1
        }

        let interval = max(notification.fireDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: mutable,
            trigger: trigger
        )
        try await center.add(request)
    }

    func removePending(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            // Time-sensitive is requested here; without it, an item set to
            // break through a Focus quietly would not.
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        } catch {
            return await authorizationStatus()
        }
        return await authorizationStatus()
    }

    func registerCategories() async {
        let done = UNNotificationAction(
            identifier: NotificationAction.done.rawValue,
            title: String(localized: "action.done"),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snooze.rawValue,
            title: String(localized: "action.snooze"),
            options: []
        )
        let plain = UNNotificationCategory(
            identifier: NotificationCategory.actionable.rawValue,
            actions: [done],
            intentIdentifiers: [],
            options: []
        )
        let snoozable = UNNotificationCategory(
            identifier: NotificationCategory.actionableWithSnooze.rawValue,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([plain, snoozable])
    }
}
