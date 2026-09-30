import Foundation
import SwiftData
import SwiftUI

/// Owns the store, the engine and the scheduler, and is the only place a view
/// calls to change something. Views read; this writes.
@MainActor
@Observable
final class AppModel {
    let store: DataStore
    private(set) var engine: ScheduleEngine
    private let completion = CompletionService()
    private var coordinator: ScheduleCoordinator

    /// Bumped whenever the store changes, so views recompute their plan.
    private(set) var revision: Int = 0
    /// What the last reschedule did. Surfaced in Settings.
    private(set) var lastSchedule: ScheduleOutcome = .none

    private var rescheduleTask: Task<Void, Never>?

    init(
        store: DataStore,
        notifications: any NotificationScheduling = SystemNotificationScheduler(),
        alarms: any AlarmScheduling = SystemAlarmScheduler()
    ) {
        self.store = store
        // The Live Activity controller and the widget-facing helpers read
        // through SharedStore. In the app process that has to be *this* store,
        // or there would be two model containers open on one file.
        SharedStore.override(store)

        let engine = ScheduleEngine(
            calendar: .current,
            configuration: .default,
            quietHours: SharedDefaults.quietHours
        )
        self.engine = engine
        self.coordinator = ScheduleCoordinator(
            engine: engine,
            notifications: notifications,
            alarms: alarms
        )
    }

    // MARK: - Reading

    func dayPlan(for day: Date, now: Date) -> DayPlan {
        engine.dayPlan(
            items: store.snapshots(),
            records: store.recordsByKey(),
            on: day,
            now: now
        )
    }

    func allItems() -> [Item] { store.allItems() }

    /// Writes a JSON backup and hands back the file to share.
    func exportData(now: Date = .now) throws -> URL {
        try DataTransfer.writeExport(from: store, now: now)
    }

    /// Replaces everything with the contents of a backup.
    @discardableResult
    func restoreData(from data: Data) throws -> Int {
        let payload = try DataTransfer.read(data)
        let count = DataTransfer.restore(payload, into: store)
        didChange()
        return count
    }

    /// Fires a notification five seconds from now. If this does not arrive,
    /// the problem is permission, not scheduling.
    func sendTestNotification() async -> NotificationAuthorization {
        (try? await coordinator.sendTestAlert()) ?? .denied
    }

    /// Everything needed to tell which of the surfaces is actually broken.
    ///
    /// Each of these is read from the system rather than from what the app
    /// last intended, because the whole point is to find the place where the
    /// two stopped agreeing.
    func diagnostics(now: Date = .now) async -> Diagnostics {
        Diagnostics(
            notifications: await coordinator.notificationStatus(),
            pendingWithSystem: await coordinator.pendingCount(),
            hasSharedContainer: !store.isUsingFallbackStore,
            hasWidgetExtension: InstalledBundle.hasWidgetExtension,
            widgetExtensionIsNested: InstalledBundle.widgetExtensionIsNested,
            widgetExtensionIsSigned: InstalledBundle.widgetExtensionIsSigned,
            widgetProfileMatchesApp: InstalledBundle.widgetProfileMatchesApp,
            appProfile: InstalledBundle.appProfile,
            widgetProfile: InstalledBundle.widgetProfile,
            appIdentifier: Bundle.main.bundleIdentifier ?? "",
            widgetIdentifier: InstalledBundle.widgetExtensionIdentifier,
            appGroup: AppGroup.identifier,
            grantedGroups: AppGroup.entitledGroups,
            liveActivitiesEnabled: LiveActivityController.shared.areActivitiesEnabled,
            liveActivityRunning: LiveActivityController.shared.isRunning,
            liveActivityError: LiveActivityController.shared.lastError,
            onLockScreen: SurfaceData.entries(for: .liveActivity, now: now).count,
            onHomeWidget: SurfaceData.entries(for: .homeWidget, now: now).count,
            itemsToday: SurfaceData.progress(now: now).total
        )
    }

    func weekReview(now: Date) -> WeekReview {
        engine.weekReview(
            items: store.snapshots(),
            records: store.recordsByKey(),
            now: now
        )
    }

    func items(matching preset: PresetKind) -> [Item] {
        store.allItems().filter { $0.preset == preset && !$0.isArchived }
    }

    // MARK: - Lifecycle

    /// Called once at launch: register the notification categories, then bring
    /// the schedule up to date.
    func start(now: Date = .now) async {
        await coordinator.prepare()

        // Push updates are off unless the user has pointed the app at a
        // server. With no handler set, the activity asks for no push token and
        // nothing ever leaves the device.
        if let registrar = PushRegistrar.configured() {
            LiveActivityController.shared.uploadRegistration = { registration in
                try? await registrar.send(registration)
            }
        }

        await reschedule(now: now)
    }

    /// Asks for notification and alarm permission. Onboarding calls this; the
    /// scheduler never asks on its own.
    @discardableResult
    func requestPermissions() async -> (notifications: NotificationAuthorization, alarms: AlarmAuthorization) {
        let result = await coordinator.requestPermissions()
        await reschedule()
        return result
    }

    /// The single reschedule path. Idempotent, so calling it often is cheap.
    func reschedule(now: Date = .now) async {
        // Holds whose clock ran out while the app was closed are written out
        // first, so everything below plans against a settled day.
        let settled = completion.settleElapsedHolds(store.recordsByKey(), now: now)
        if !settled.isEmpty {
            for (key, record) in settled {
                store.record(for: key).state = record
            }
            store.save()
        }

        lastSchedule = await coordinator.refresh(
            items: store.snapshots(),
            records: store.recordsByKey(),
            now: now
        )
        // The card, the widgets and the notifications all describe the same
        // day, so they are brought into line together or not at all.
        await LiveActivityController.shared.refresh(now: now)
        await coordinator.refreshDaySummary(
            plan: dayPlan(for: now, now: now),
            enabled: SharedDefaults.lockScreenSummary,
            now: now
        )
        await SurfaceRefresh.reloadAll()
    }

    // MARK: - Writing

    @discardableResult
    func complete(
        _ occurrence: ResolvedOccurrence,
        now: Date = .now,
        answer: String? = nil
    ) -> CompletionOutcome {
        let row = store.record(for: occurrence.key)
        let (updated, outcome) = completion.complete(
            row.state,
            item: occurrence.item,
            now: now,
            answer: answer
        )
        row.state = updated
        store.save()

        // Silence this one straight away rather than waiting for the reschedule
        // below: a nag that fires between the tap and the refresh is exactly
        // the thing that makes an app feel broken.
        if case .completed = outcome {
            Task { await coordinator.cancelAlerts(for: occurrence.key) }
        }
        didChange()
        return outcome
    }

    /// "I did not do this." Different from letting the window close on its own,
    /// and different from done: it clears the row without claiming credit.
    func markNotDone(_ occurrence: ResolvedOccurrence, now: Date = .now) {
        let row = store.record(for: occurrence.key)
        var updated = completion.markMissed(row.state, now: now)
        updated.completedAt = nil
        updated.snoozedUntil = nil
        row.state = updated
        store.save()
        Task { await coordinator.cancelAlerts(for: occurrence.key) }
        didChange()
    }

    /// Deletes the item this occurrence belongs to, and everything it ever did.
    func deleteItem(of occurrence: ResolvedOccurrence) {
        guard let item = store.item(with: occurrence.item.id) else { return }
        delete(item)
    }

    func reopen(_ occurrence: ResolvedOccurrence) {
        let row = store.record(for: occurrence.key)
        row.state = completion.reopen(row.state, item: occurrence.item)
        store.save()
        didChange()
        Task { await reschedule() }
    }

    @discardableResult
    func snooze(_ occurrence: ResolvedOccurrence, now: Date = .now) -> Bool {
        let row = store.record(for: occurrence.key)
        guard let updated = completion.snooze(row.state, item: occurrence.item, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        Task { await coordinator.cancelAlerts(for: occurrence.key) }
        didChange()
        return true
    }

    @discardableResult
    func start(_ occurrence: ResolvedOccurrence, now: Date = .now) -> Bool {
        let row = store.record(for: occurrence.key)
        guard let updated = completion.start(row.state, item: occurrence.item, now: now) else {
            return false
        }
        row.state = updated
        store.save()
        didChange()
        return true
    }

    /// Applies a Done or Snooze tapped on a notification. Runs from a cold
    /// start, so it resolves the occurrence from the store rather than assuming
    /// a screen is showing it.
    func apply(_ action: NotificationAction?, to key: OccurrenceKey, now: Date = .now) async {
        guard let item = store.item(with: key.itemID) else { return }
        let snapshot = item.snapshot
        let row = store.record(for: key)

        switch action {
        case .some(.done):
            let (updated, _) = completion.complete(row.state, item: snapshot, now: now)
            row.state = updated
        case .some(.snooze):
            guard let updated = completion.snooze(row.state, item: snapshot, now: now) else { return }
            row.state = updated
        case nil:
            // The notification itself was tapped, not one of its buttons.
            // Opening the app is the whole action.
            return
        }

        store.save()
        await coordinator.cancelAlerts(for: key)
        didChange()
        await reschedule(now: now)
    }

    func createItem(title: String, notes: String, preset: PresetKind, settings: ItemSettings, now: Date = .now) {
        let item = Item(
            title: title,
            notes: notes,
            preset: preset,
            settings: settings,
            createdAt: now
        )
        store.insert(item)
        didChange()
    }

    func update(_ item: Item, title: String, notes: String, settings: ItemSettings, now: Date = .now) {
        let itemID = item.id
        item.title = title
        item.notes = notes
        item.settings = settings
        item.updatedAt = now
        store.save()
        // Settings may have moved or removed every alert this item had.
        Task { await coordinator.cancelAlerts(forItem: itemID) }
        didChange()
    }

    func delete(_ item: Item) {
        let itemID = item.id
        store.delete(item)
        Task { await coordinator.cancelAlerts(forItem: itemID) }
        didChange()
    }

    func setArchived(_ item: Item, _ archived: Bool) {
        let itemID = item.id
        item.isArchived = archived
        store.save()
        if archived {
            Task { await coordinator.cancelAlerts(forItem: itemID) }
        }
        didChange()
    }

    func updateQuietHours(_ quietHours: QuietHours) {
        SharedDefaults.quietHours = quietHours
        let updated = ScheduleEngine(
            calendar: .current,
            configuration: engine.configuration,
            quietHours: quietHours
        )
        engine = updated
        // The coordinator holds its own copy, and quiet hours decide which
        // alerts are allowed to exist at all, so it has to see the change too.
        coordinator.engine = updated
        didChange()
    }

    /// Bumps the revision the views watch, and queues a reschedule. Successive
    /// edits collapse into one refresh rather than one per keystroke.
    private func didChange() {
        revision &+= 1
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }
}

/// A snapshot of what the system says, for the Settings screen. Nothing here
/// is derived: every field is asked of iOS at the moment it is read.
nonisolated struct Diagnostics: Sendable, Equatable {
    var notifications: NotificationAuthorization = .notDetermined
    var pendingWithSystem = 0
    var hasSharedContainer = false
    var hasWidgetExtension = false
    /// iOS only registers an extension whose identifier sits under the
    /// app's. A re-signing tool that renames one and not the other
    /// produces an app that runs and a widget that never appears.
    var widgetExtensionIsNested = false
    /// Present in the bundle is not the same as signed. iOS refuses to
    /// register an unsigned extension, and the app around it runs perfectly.
    var widgetExtensionIsSigned = false
    var widgetProfileMatchesApp = false
    var appProfile: ProvisioningProfile?
    var widgetProfile: ProvisioningProfile?
    var appIdentifier = ""
    var widgetIdentifier: String?
    /// The group the app settled on, and the ones its signature actually
    /// grants. When these disagree the widgets cannot see anything.
    var appGroup = ""
    var grantedGroups: [String] = []
    var liveActivitiesEnabled = false
    var liveActivityRunning = false
    /// ActivityKit's own words for why the card was refused.
    var liveActivityError: String?
    var onLockScreen = 0
    var onHomeWidget = 0
    /// Everything on today's plan, done or not. Without it there is no telling
    /// "nothing is set to show" from "there is nothing today".
    var itemsToday = 0
}
