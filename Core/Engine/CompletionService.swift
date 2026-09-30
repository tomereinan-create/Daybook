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
    /// Done started a clock instead of finishing the thing. The item is being
    /// done until the date given, and finishes by itself when it arrives.
    case holding(until: Date)
}

/// Pure transformations of a single occurrence record. No storage, no UI, so
/// the same code runs from the app, the widget intent and the notification
/// action, and can be tested on its own.
nonisolated struct CompletionService: Sendable {
    init() {}

    func complete(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot,
        now: Date,
        answer: String? = nil
    ) -> (record: OccurrenceStateRecord, outcome: CompletionOutcome) {
        var updated = record
        updated.snoozedUntil = nil
        if let answer {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.answer = trimmed.isEmpty ? nil : trimmed
        }

        // Pressing Done while a hold is running finishes it early rather than
        // starting the clock again. Somebody who taps twice means "enough".
        if updated.holdUntil != nil {
            updated.holdUntil = nil
            updated.completedAt = now
            return (updated, .completed)
        }

        // A routine advances one step at a time and only finishes on the last.
        let steps = item.settings.steps
        if !steps.isEmpty {
            let next = record.currentStepIndex + 1
            if next < steps.count {
                updated.currentStepIndex = next
                return (updated, .advancedToStep(next))
            }
            updated.currentStepIndex = steps.count
            let outcome = finish(&updated, item: item, now: now)
            return (updated, outcome)
        }

        // A quota habit tallies until it reaches its target.
        if case .quota(let target, _) = item.settings.recurrence.frequency {
            let count = record.completionCount + 1
            updated.completionCount = count
            if count >= target {
                let outcome = finish(&updated, item: item, now: now)
                return (updated, outcome)
            }
            return (updated, .tallied(count: count, target: target))
        }

        let outcome = finish(&updated, item: item, now: now)
        return (updated, outcome)
    }

    /// The last step of finishing: either it is done, or it now runs for a
    /// while and is done when that runs out. Every path into completion goes
    /// through here so a hold cannot be skipped by finishing a routine or
    /// filling a quota instead.
    private func finish(
        _ updated: inout OccurrenceStateRecord,
        item: ItemSnapshot,
        now: Date
    ) -> CompletionOutcome {
        if let minutes = item.settings.holdDuration {
            let until = now.addingTimeInterval(TimeInterval(minutes) * 60)
            updated.holdUntil = until
            return .holding(until: until)
        }
        updated.completedAt = now
        return .completed
    }

    /// Undo. Steps and tallies step back by one; everything else reopens.
    func reopen(
        _ record: OccurrenceStateRecord,
        item: ItemSnapshot
    ) -> OccurrenceStateRecord {
        var updated = record
        updated.completedAt = nil
        updated.missedAt = nil
        // A running clock stops too. The answer stays: undoing a tap should
        // not throw away a number the user typed.
        updated.holdUntil = nil

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

nonisolated extension CompletionService {
    /// Writes out holds whose clock has run out.
    ///
    /// The resolver already shows these as done, because they are; this makes
    /// the store agree, so the week's review counts them and the row is not
    /// recalculated from a date in the past forever. Called from the same
    /// reschedule that runs on launch, on every change and in the background.
    func settleElapsedHolds(
        _ records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> [OccurrenceKey: OccurrenceStateRecord] {
        var settled: [OccurrenceKey: OccurrenceStateRecord] = [:]
        for (key, record) in records {
            guard let hold = record.holdUntil, now >= hold, record.completedAt == nil else { continue }
            var updated = record
            updated.holdUntil = nil
            // Finished when the clock ran out, not when the app noticed.
            updated.completedAt = hold
            settled[key] = updated
        }
        return settled
    }
}
