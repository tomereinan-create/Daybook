import Foundation

/// Turns a generated occurrence plus its stored state into the answer every
/// surface needs: when it actually fires, when it goes away, and where it
/// stands right now.
nonisolated struct StateResolver: Sendable {
    var calendar: Calendar
    var configuration: EngineConfiguration

    init(calendar: Calendar, configuration: EngineConfiguration = .default) {
        self.calendar = calendar
        self.configuration = configuration
    }

    func resolve(
        item: ItemSnapshot,
        generated: GeneratedOccurrence,
        record: OccurrenceStateRecord?,
        now: Date,
        quota: QuotaProgress? = nil
    ) -> ResolvedOccurrence {
        let record = record ?? OccurrenceStateRecord(key: generated.key)
        let trigger = effectiveTrigger(item: item, generated: generated, record: record, now: now)
        let window = windowEnd(for: item, trigger: trigger, generated: generated)
        let state = state(item: item, record: record, trigger: trigger, window: window, now: now)

        return ResolvedOccurrence(
            item: item,
            generated: generated,
            record: record,
            state: state,
            effectiveTrigger: trigger,
            windowEnd: window,
            quotaProgress: quota
        )
    }

    // MARK: - Trigger

    /// When a countdown's clock started.
    ///
    /// A timer the user tapped Start on counts from that tap. One set to run
    /// on its own counts from when it came into being — the later of the
    /// item's creation and the start of the occurrence's own slot, so that a
    /// repeat does not count from the day the item was first made.
    func relativeOrigin(
        item: ItemSnapshot,
        generated: GeneratedOccurrence,
        record: OccurrenceStateRecord
    ) -> Date? {
        if let started = record.startedAt { return started }
        guard item.settings.trigger.runsUnattended else { return nil }
        return max(item.createdAt, generated.slot)
    }

    /// The instant alerts hang off, after snoozing, manual starts and roll-over
    /// have been applied.
    func effectiveTrigger(
        item: ItemSnapshot,
        generated: GeneratedOccurrence,
        record: OccurrenceStateRecord,
        now: Date
    ) -> Date? {
        if let snoozed = record.snoozedUntil {
            return snoozed
        }

        let settings = item.settings
        var base: Date?

        switch settings.trigger.kind {
        case .time:
            base = generated.triggerDate
        case .relative:
            if let origin = relativeOrigin(item: item, generated: generated, record: record),
               let minutes = settings.trigger.relativeMinutes {
                base = origin.addingTimeInterval(TimeInterval(minutes) * 60)
            } else {
                base = nil
            }
        case .location, .afterPrevious, .none:
            base = nil
        }

        guard var trigger = base, record.completedAt == nil else { return base }

        // Roll-over: the occurrence keeps its identity but its trigger walks
        // forward a day at a time until its window covers the present.
        if settings.dismissal.onMissed == .rollOver {
            var steps = 0
            while let end = windowEnd(for: item, trigger: trigger, generated: generated),
                  now >= end,
                  steps < 400 {
                trigger = calendar.date(byAdding: .day, value: 1, to: trigger) ?? trigger
                steps += 1
            }
        }
        return trigger
    }

    // MARK: - Window

    /// When the occurrence stops being shown. `nil` means it stays until done.
    func windowEnd(for item: ItemSnapshot, trigger: Date?, generated: GeneratedOccurrence) -> Date? {
        switch item.settings.dismissal.endCondition {
        case .markedDone, .manualOnly:
            return nil
        case .eventStart:
            return trigger
        case .windowEnds(let duration):
            guard let trigger else { return nil }
            return trigger.addingTimeInterval(duration)
        case .atTime(let time):
            let day = trigger ?? generated.slot
            guard let candidate = calendar.date(setting: time, on: day) else { return nil }
            if let trigger, candidate <= trigger {
                return calendar.date(byAdding: .day, value: 1, to: candidate)
            }
            return candidate
        }
    }

    // MARK: - State

    func state(
        item: ItemSnapshot,
        record: OccurrenceStateRecord,
        trigger: Date?,
        window: Date?,
        now: Date
    ) -> OccurrenceState {
        if record.completedAt != nil { return .done }
        // Done started a clock rather than stopping one. While it runs the
        // item is being done — which is what `.active` means — and when it
        // runs out the item is finished, whatever else the day says.
        if let hold = record.holdUntil {
            return now < hold ? .active : .done
        }
        // The user said they did not do it. That is a different answer from
        // "the window closed", and it outranks the clock: they have decided.
        if record.missedAt != nil { return .missed }
        if let snoozed = record.snoozedUntil, snoozed > now { return .snoozed }

        guard let trigger else {
            // No calendar-bound trigger: undated tasks, quota habits, location
            // reminders and timers that have not been started. They are simply
            // outstanding until completed.
            return .visible
        }

        if let window, now >= window {
            return item.settings.dismissal.onMissed == .becomeOpenTask ? .overdue : .missed
        }

        if now >= trigger {
            if case .windowEnds = item.settings.dismissal.endCondition, window != nil {
                return .active
            }
            return now < trigger.addingTimeInterval(configuration.dueGrace) ? .due : .overdue
        }

        // A running timer is running, whatever its lead time says. Lead time
        // answers "how early should this appear"; a timer whose clock has
        // started is already here, and it should stay on screen counting down
        // rather than vanish until it goes off. Reaching this line at all
        // means the countdown has an origin — an unstarted one has no trigger
        // and left through the guard above.
        if item.settings.trigger.kind == .relative {
            return .active
        }

        let leadTime = max(item.settings.visibility.leadTime, 0)
        if now >= trigger.addingTimeInterval(-leadTime) { return .visible }
        return .upcoming
    }
}

nonisolated extension ResolvedOccurrence {
    /// True when the window closed because the thing simply happened, not
    /// because the user let it slip. Events are the only case today, and the
    /// Today screen files them under "Earlier" rather than "Missed".
    var concludedNaturally: Bool {
        if case .eventStart = item.settings.dismissal.endCondition { return true }
        return false
    }

    /// The section the Today screen files this occurrence under.
    var daySection: DaySection {
        switch state {
        case .done:
            return .done
        case .missed:
            return concludedNaturally ? .done : .missed
        case .overdue, .due, .active:
            return .now
        case .visible:
            return effectiveTrigger == nil ? .undated : .now
        case .upcoming, .snoozed:
            return .upcoming
        }
    }
}
