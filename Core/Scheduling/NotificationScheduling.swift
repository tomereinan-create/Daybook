import Foundation
import UserNotifications

nonisolated enum NotificationAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
    /// Allowed, but only into Notification Centre. No banners, no sound.
    case provisional

    var canPost: Bool { self == .authorized || self == .provisional }
}

/// Where iOS has been told this app's notifications may appear.
///
/// Permission is not one switch but several. An app can be fully authorized
/// and still be kept off the lock screen, in which case everything arrives,
/// everything is delivered, and the lock screen stays empty — which looks
/// exactly like a broken app and is not one.
nonisolated enum NotificationPlacement: String, Sendable, Hashable {
    case enabled
    case disabled
    case notSupported
}

nonisolated struct NotificationPlacements: Sendable, Hashable {
    var lockScreen: NotificationPlacement = .notSupported
    var notificationCentre: NotificationPlacement = .notSupported
    var banners: NotificationPlacement = .notSupported

    /// The one that matters for a standing day summary.
    var reachesLockScreen: Bool { lockScreen == .enabled }
}

/// The surface the scheduler needs from iOS.
///
/// A protocol so the reconciliation can be tested without a notification
/// centre, and so nothing has to pass a non-`Sendable` `UNNotificationRequest`
/// across an isolation boundary — the live implementation builds the request
/// from value types on the other side.
nonisolated protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> Set<String>
    /// What iOS is currently showing, as opposed to holding for later.
    func deliveredIdentifiers() async -> Set<String>
    func add(_ notification: PlannedNotification, content: NotificationContent) async throws
    func removePending(identifiers: [String]) async
    func removeDelivered(identifiers: [String]) async
    func authorizationStatus() async -> NotificationAuthorization
    func placements() async -> NotificationPlacements
    func requestAuthorization() async -> NotificationAuthorization
    func registerCategories() async
    /// Posts the standing day summary, or takes it down when given `nil`.
    func postSummary(_ summary: DaySummary?) async
    func sendTest() async throws
}

/// The real thing.
nonisolated struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    init() {}

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }

    func deliveredIdentifiers() async -> Set<String> {
        let delivered = await center.deliveredNotifications()
        return Set(delivered.map(\.request.identifier))
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
        do {
            try await center.add(
                UNNotificationRequest(identifier: notification.id, content: mutable, trigger: trigger)
            )
        } catch {
            // A time-sensitive level needs an entitlement this build may not
            // hold — a sideloaded one never does. Better an ordinary alert
            // than no alert, so drop a rung and try once more.
            guard mutable.interruptionLevel == .timeSensitive else { throw error }
            mutable.interruptionLevel = .active
            try await center.add(
                UNNotificationRequest(identifier: notification.id, content: mutable, trigger: trigger)
            )
        }
    }

    func postSummary(_ summary: DaySummary?) async {
        guard let summary else {
            center.removeDeliveredNotifications(withIdentifiers: [DaySummary.identifier])
            center.removePendingNotificationRequests(withIdentifiers: [DaySummary.identifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        // Active and silent. Passive was the obvious choice for a standing
        // note and it was wrong: Apple's own words for it are "adds the
        // notification to the notification list without lighting up the
        // screen", so locking the phone showed nothing and the whole feature
        // looked dead. Active lights the screen; `sound = nil` keeps it
        // quiet. What stops it becoming a nuisance is that it is only
        // reposted when the day actually changed, which the caller decides.
        content.interruptionLevel = .active
        content.sound = nil
        content.threadIdentifier = DaySummary.identifier
        content.relevanceScore = 1
        if let next = summary.next {
            content.categoryIdentifier = summary.nextSnoozeMinutes == nil
                ? NotificationCategory.actionable.rawValue
                : NotificationCategory.actionableWithSnooze.rawValue
            var info = [
                NotificationUserInfoKey.itemID: next.itemID.uuidString,
                NotificationUserInfoKey.slot: String(Int(next.slot.timeIntervalSince1970))
            ]
            if let minutes = summary.nextSnoozeMinutes {
                info[NotificationUserInfoKey.snoozeMinutes] = String(minutes)
            }
            content.userInfo = info
        }

        // Taken down first, then posted again. Adding under an existing
        // identifier replaces the notification, but iOS still treats it as
        // the one already seen — it stays wherever it was filed instead of
        // arriving. Removing it first makes what follows genuinely new, which
        // is what puts it on the lock screen rather than three swipes into
        // Notification Centre.
        center.removeDeliveredNotifications(withIdentifiers: [DaySummary.identifier])

        // No trigger at all: delivered now.
        try? await center.add(
            UNNotificationRequest(identifier: DaySummary.identifier, content: content, trigger: nil)
        )
    }

    /// Posts one alert a few seconds from now, so "did I allow notifications?"
    /// can be answered without waiting for a real item to come due.
    func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "settings.test.title")
        content.body = String(localized: "settings.test.body")
        content.sound = .default
        try await center.add(
            UNNotificationRequest(
                identifier: "daybook.test.\(Int(Date.now.timeIntervalSince1970))",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
        )
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

    func placements() async -> NotificationPlacements {
        let settings = await center.notificationSettings()
        func map(_ setting: UNNotificationSetting) -> NotificationPlacement {
            switch setting {
            case .enabled: .enabled
            case .disabled: .disabled
            case .notSupported: .notSupported
            @unknown default: .notSupported
            }
        }
        return NotificationPlacements(
            lockScreen: map(settings.lockScreenSetting),
            notificationCentre: map(settings.notificationCenterSetting),
            banners: map(settings.alertSetting)
        )
    }

    func requestAuthorization() async -> NotificationAuthorization {
        // Only the three options every build is allowed to ask for.
        //
        // This used to include `.timeSensitive`, which has been deprecated
        // since iOS 15 in favour of an entitlement — and a sideloaded build
        // holds no entitlements at all. Asking for something the build cannot
        // have put the one call that gates every alert in the app at risk of
        // failing before the prompt was ever shown. Breaking through a Focus
        // is decided by the interruption level on each alert, which already
        // degrades on its own when the entitlement is missing.
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
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
