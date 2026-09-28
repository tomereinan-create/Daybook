import Foundation

/// The outcome of one reschedule, for the diagnostics row in Settings and for
/// the tests.
nonisolated struct ScheduleOutcome: Sendable, Equatable {
    var added: Int
    var removed: Int
    var kept: Int
    var alarmsScheduled: Int
    var alarmsCancelled: Int
    /// Alerts the 64-request budget refused to take.
    var droppedByBudget: Int
    var notificationAuthorization: NotificationAuthorization
    var alarmAuthorization: AlarmAuthorization

    static let none = ScheduleOutcome(
        added: 0, removed: 0, kept: 0,
        alarmsScheduled: 0, alarmsCancelled: 0, droppedByBudget: 0,
        notificationAuthorization: .notDetermined,
        alarmAuthorization: .notDetermined
    )
}

/// Turns the engine's plan into what iOS actually holds.
///
/// One entry point, `refresh(items:records:now:)`, called on launch, on every
/// data change, from the background refresh task, and after an alarm is
/// dismissed. It is idempotent: running it twice in a row changes nothing the
/// second time, which is what makes it safe to call that often.
nonisolated struct ScheduleCoordinator: Sendable {
    var engine: ScheduleEngine
    var notifications: any NotificationScheduling
    var alarms: any AlarmScheduling
    var reconciler = NotificationReconciler()
    var builder = NotificationContentBuilder()

    init(
        engine: ScheduleEngine,
        notifications: any NotificationScheduling,
        alarms: any AlarmScheduling
    ) {
        self.engine = engine
        self.notifications = notifications
        self.alarms = alarms
    }

    @discardableResult
    func refresh(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) async -> ScheduleOutcome {
        let notificationAuth = await notifications.authorizationStatus()
        let alarmAuth = await alarms.authorizationStatus()
        let plan = engine.notificationPlan(items: items, records: records, now: now)

        var outcome = ScheduleOutcome.none
        outcome.droppedByBudget = plan.droppedCount
        outcome.notificationAuthorization = notificationAuth
        outcome.alarmAuthorization = alarmAuth

        // Without permission there is nothing to reconcile against, and asking
        // for it is the onboarding's job, not this one's. Everything still
        // appears on the surfaces; it just does not buzz.
        if notificationAuth.canPost {
            let pending = await notifications.pendingIdentifiers()
            let work = reconciler.reconcile(plan: plan.notifications, pending: pending)

            await notifications.removePending(identifiers: work.toRemove)
            for planned in work.toAdd {
                try? await notifications.add(planned, content: builder.content(for: planned))
            }
            outcome.added = work.toAdd.count
            outcome.removed = work.toRemove.count
            outcome.kept = work.unchanged.count
        }

        if alarmAuth.canSchedule {
            let existing = await alarms.scheduledIdentifiers()
            let wanted = Set(plan.alarms.map(\.alarmID))

            let stale = existing.subtracting(wanted)
            await alarms.cancel(ids: stale.sorted { $0.uuidString < $1.uuidString })
            outcome.alarmsCancelled = stale.count

            // Alarms are re-scheduled under the same identifier rather than
            // diffed: a repeating alarm's next fire date moves every day, and
            // AlarmKit replaces by id.
            for alarm in plan.alarms {
                try? await alarms.schedule(alarm)
            }
            outcome.alarmsScheduled = plan.alarms.count
        }

        return outcome
    }

    /// Cancels every pending alert for one occurrence, now, without waiting for
    /// a full reschedule. The brief is explicit that completing something from
    /// any surface has to silence its nags immediately.
    func cancelAlerts(for key: OccurrenceKey) async {
        let pending = await notifications.pendingIdentifiers()
        let mine = reconciler.identifiers(in: pending, for: key)
        await notifications.removePending(identifiers: mine)
        await notifications.removeDelivered(identifiers: mine)
    }

    /// Cancels everything belonging to an item, for delete and archive.
    func cancelAlerts(forItem itemID: UUID) async {
        let pending = await notifications.pendingIdentifiers()
        let mine = reconciler.identifiers(in: pending, forItem: itemID)
        await notifications.removePending(identifiers: mine)
        await notifications.removeDelivered(identifiers: mine)
    }

    func prepare() async {
        await notifications.registerCategories()
    }

    @discardableResult
    func requestPermissions() async -> (notifications: NotificationAuthorization, alarms: AlarmAuthorization) {
        let granted = await notifications.requestAuthorization()
        let alarmed = await alarms.requestAuthorization()
        return (granted, alarmed)
    }
}
