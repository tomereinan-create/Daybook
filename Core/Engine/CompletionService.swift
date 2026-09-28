import Foundation

/// What a tap on a completion circle actually did. The surfaces use this to
/// decide what to say back to the user.
nonisolated enum CompletionOutcome: Sendable, Hashable {
    /// The occurrence is finished.
    case completed
    /// A routine moved on; the value is the new step index.
    case advancedToStep(Int)
    /// A quota habit was tallied; the values are the new count and the target.
    case tallied(count: Int, target: Int)
}

/// Pure transformations of a single occurrence record. No storage, no UI, so
/// the same code runs from the app, the widget intent and the notification
/// action, and can be tested on its own.
nonisolated struct CompletionService: Sendable {
    init() {}

    func complete(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot,
        now: Date
    ) -> (record: OccurrenceStateRecord, outcome: CompletionOutcome) {
        var updated = record
        updated.snoozedUntil = nil

        // A routine advances one step at a time and only finishes on the last.
        let steps = item.settings.steps
        if !steps.isEmpty {
            let next = record.currentStepIndex + 1
            if next < steps.count {
                updated.currentStepIndex = next
                return (updated, .advancedToStep(next))
            }
            updated.currentStepIndex = steps.count
            updated.completedAt = now
            return (updated, .completed)
        }

        // A quota habit tallies until it reaches its target.
        if case .quota(let target, _) = item.settings.recurrence.frequency {
            let count = record.completionCount + 1
            updated.completionCount = count
            if count >= target {
                updated.completedAt = now
                return (updated, .completed)
            }
            return (updated, .tallied(count: count, target: target))
        }

        updated.completedAt = now
        return (updated, .completed)
    }

    /// Undo. Steps and tallies step back by one; everything else reopens.
    func reopen(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot
    ) -> OccurrenceStateRecord {
        var updated = record
        updated.completedAt = nil
        updated.missedAt = nil

        if !item.settings.steps.isEmpty {
            updated.currentStepIndex = max(record.currentStepIndex - 1, 0)
        }
        if case .quota = item.settings.recurrence.frequency {
            updated.completionCount = max(record.completionCount - 1, 0)
        }
        return updated
    }

    /// Returns `nil` when the item does not allow snoozing, so a surface can
    /// hide the button rather than offer one that does nothing.
    func snooze(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot,
        now: Date
    ) -> OccurrenceStateRecord? {
        let alerting = item.settings.alerting
        guard alerting.snoozeAllowed else { return nil }
        var updated = record
        updated.snoozedUntil = now.addingTimeInterval(TimeInterval(max(alerting.snoozeMinutes, 1)) * 60)
        updated.nagsFired = 0
        return updated
    }

    /// Starts a relative timer. Returns `nil` for items that are not started
    /// by hand, and for one that is already running.
    func start(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot,
        now: Date
    ) -> OccurrenceStateRecord? {
        guard item.settings.trigger.kind == .relative, record.startedAt == nil else { return nil }
        var updated = record
        updated.startedAt = now
        return updated
    }

    /// Records that a window closed unfinished. The caller decides when, from
    /// the resolved state.
    func markMissed(_ record: OccurrenceStateRecord, now: Date) -> OccurrenceStateRecord {
        var updated = record
        if updated.missedAt == nil { updated.missedAt = now }
        return updated
    }
}
