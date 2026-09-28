import Foundation
import UserNotifications

/// Handles taps on a notification's Done and Snooze buttons.
///
/// The action arrives whether the app was running or not, so everything here
/// has to work from a cold start: find the occurrence from the payload, apply
/// the same `CompletionService` the UI uses, then reschedule.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let handle: @MainActor (OccurrenceKey, NotificationAction?) async -> Void

    init(handle: @escaping @MainActor (OccurrenceKey, NotificationAction?) async -> Void) {
        self.handle = handle
    }

    /// Show an alert even while the app is open. An item that asked to be
    /// interrupted about should interrupt, not be swallowed because the user
    /// happens to be looking at a different screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let key = Self.occurrenceKey(from: info) else { return }
        let action = NotificationAction(rawValue: response.actionIdentifier)
        await handle(key, action)
    }

    /// Rebuilds the occurrence identity from the notification payload.
    static func occurrenceKey(from userInfo: [AnyHashable: Any]) -> OccurrenceKey? {
        guard let rawID = userInfo[NotificationUserInfoKey.itemID] as? String,
              let itemID = UUID(uuidString: rawID),
              let rawSlot = userInfo[NotificationUserInfoKey.slot] as? String,
              let seconds = TimeInterval(rawSlot)
        else { return nil }
        return OccurrenceKey(itemID: itemID, slot: Date(timeIntervalSince1970: seconds))
    }
}
