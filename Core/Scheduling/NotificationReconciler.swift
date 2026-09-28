import Foundation

/// What has to change to make the pending requests match the plan.
nonisolated struct NotificationReconciliation: Sendable, Equatable {
    /// Requests to register. Already inside the budget.
    var toAdd: [PlannedNotification]
    /// Identifiers to cancel, because they are no longer planned or their time
    /// moved.
    var toRemove: [String]
    /// Identifiers already pending and still wanted. Left alone: re-adding
    /// would churn the system's queue for nothing.
    var unchanged: [String]

    var isEmpty: Bool { toAdd.isEmpty && toRemove.isEmpty }
}

/// Diffs a plan against what iOS currently holds.
///
/// This is deliberately a pure function over two sets of identifiers. The whole
/// rolling-window behaviour — add what is new, drop what expired, leave the
/// rest — is decided here where it can be tested, and `NotificationScheduler`
/// only carries out the result.
nonisolated struct NotificationReconciler: Sendable {
    init() {}

    func reconcile(
        plan: [PlannedNotification],
        pending: Set<String>
    ) -> NotificationReconciliation {
        let planned = Set(plan.map(\.id))

        let toAdd = plan.filter { !pending.contains($0.id) }
        let toRemove = pending.subtracting(planned).sorted()
        let unchanged = pending.intersection(planned).sorted()

        return NotificationReconciliation(
            toAdd: toAdd.sorted { $0.fireDate < $1.fireDate },
            toRemove: toRemove,
            unchanged: unchanged
        )
    }

    /// Identifiers belonging to one occurrence. Used to cancel a family of
    /// pending nags the instant it is completed, without waiting for a full
    /// reschedule.
    func identifiers(in pending: Set<String>, for key: OccurrenceKey) -> [String] {
        let prefix = NotificationPlanner.prefix(for: key)
        return pending.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Identifiers belonging to one item, whatever occurrence. Used when an
    /// item is deleted or archived.
    func identifiers(in pending: Set<String>, forItem itemID: UUID) -> [String] {
        let prefix = NotificationPlanner.itemPrefix(for: itemID)
        return pending.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
