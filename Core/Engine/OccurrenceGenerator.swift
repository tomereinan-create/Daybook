import Foundation

/// Turns an item's recurrence into the concrete occurrences that fall in a
/// date range. Knows nothing about completion, alerts or surfaces.
struct OccurrenceGenerator: Sendable {
    var calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Occurrences whose slot lies in `[range.lowerBound, range.upperBound)`.
    func occurrences(for item: ItemSnapshot, in range: Range<Date>) -> [GeneratedOccurrence] {
        guard !item.isArchived, range.lowerBound < range.upperBound else { return [] }
        let settings = item.settings

        switch settings.recurrence.frequency {
        case .once:
            return singleOccurrence(for: item, in: range).map { [$0] } ?? []
        case .quota(let count, let period):
            return quotaOccurrences(for: item, count: count, period: period, in: range)
        case .daily, .weekdays, .everyNDays, .dayOfMonth:
            return repeatingOccurrences(for: item, in: range)
        }
    }

    // MARK: - One-off

    private func singleOccurrence(for item: ItemSnapshot, in range: Range<Date>) -> GeneratedOccurrence? {
        let slot: Date
        if item.settings.trigger.isCalendarBound {
            guard let date = calendarBoundDate(for: item, on: item.settings.trigger.date ?? item.createdAt) else {
                return nil
            }
            slot = date
        } else {
            // Undated: tasks, someday, waiting-for, location reminders and
            // relative timers all get one slot that never moves.
            slot = calendar.startOfDay(for: item.createdAt)
        }
        guard range.contains(slot) else { return nil }
        return GeneratedOccurrence(
            key: OccurrenceKey(itemID: item.id, slot: slot),
            triggerDate: item.settings.trigger.isCalendarBound ? slot : nil,
            ordinal: 0,
            quotaPeriod: nil
        )
    }

    // MARK: - Repeating

    private func repeatingOccurrences(for item: ItemSnapshot, in range: Range<Date>) -> [GeneratedOccurrence] {
        let recurrence = item.settings.recurrence
        let anchorDay = calendar.startOfDay(for: recurrence.anchorDate)
        var result: [GeneratedOccurrence] = []

        // Walk days rather than seconds so DST never shifts the day cursor.
        // Start one day early: a late-evening trigger on the previous day can
        // still land inside the range once the time of day is applied.
        var day = calendar.startOfDay(for: range.lowerBound)
        day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let lastDay = calendar.startOfDay(for: range.upperBound)

        // Hard stop: even a ten-year range cannot spin forever.
        var guardCounter = 0
        let guardLimit = 4_000

        while day <= lastDay && guardCounter < guardLimit {
            guardCounter += 1
            defer { day = calendar.startOfNextDay(after: day) }

            guard day >= anchorDay, matches(day: day, frequency: recurrence.frequency, anchorDay: anchorDay) else {
                continue
            }
            guard let ordinal = ordinal(of: day, frequency: recurrence.frequency, anchorDay: anchorDay) else {
                continue
            }
            // Days ascend and both end conditions only ever run out, so the
            // first day past the end means no later day can qualify either.
            guard withinEnd(recurrence.end, ordinal: ordinal, day: day) else { break }
            guard let slot = calendarBoundDate(for: item, on: day) else { continue }
            guard range.contains(slot) else { continue }

            result.append(
                GeneratedOccurrence(
                    key: OccurrenceKey(itemID: item.id, slot: slot),
                    triggerDate: item.settings.trigger.isCalendarBound ? slot : nil,
                    ordinal: ordinal,
                    quotaPeriod: nil
                )
            )
        }
        return result
    }

    /// The slot instant for a given day: the item's time of day when it has
    /// one, otherwise midnight.
    private func calendarBoundDate(for item: ItemSnapshot, on day: Date) -> Date? {
        let trigger = item.settings.trigger
        if trigger.kind == .time, let time = trigger.timeOfDay {
            return calendar.date(setting: time, on: day)
        }
        if trigger.kind == .time, let date = trigger.date, !item.settings.recurrence.frequency.repeats {
            return date
        }
        if trigger.kind == .time, let date = trigger.date {
            // A recurring item that only carries an absolute date reuses that
            // date's time of day on every occurrence day.
            return calendar.date(setting: calendar.timeOfDay(of: date), on: day)
        }
        return calendar.startOfDay(for: day)
    }

    private func matches(day: Date, frequency: Frequency, anchorDay: Date) -> Bool {
        switch frequency {
        case .once, .quota:
            return false
        case .daily:
            return true
        case .weekdays(let days):
            return days.contains(calendar.weekday(of: day))
        case .everyNDays(let n):
            let step = max(n, 1)
            let delta = calendar.dayCount(from: anchorDay, to: day)
            return delta >= 0 && delta % step == 0
        case .dayOfMonth(let wanted):
            let last = calendar.lastDayOfMonth(containing: day)
            let effective = min(max(wanted, 1), last)
            return calendar.component(.day, from: day) == effective
        }
    }

    /// Zero-based position of `day` in the recurrence, computed in closed form
    /// so that a hundredth occurrence costs the same as the first.
    func ordinal(of day: Date, frequency: Frequency, anchorDay: Date) -> Int? {
        let delta = calendar.dayCount(from: anchorDay, to: day)
        guard delta >= 0 else { return nil }

        switch frequency {
        case .once:
            return 0
        case .daily:
            return delta
        case .everyNDays(let n):
            return delta / max(n, 1)
        case .weekdays(let days):
            guard !days.isEmpty else { return nil }
            // Count matching days in the closed interval [anchor, day].
            let span = delta + 1
            let fullWeeks = span / 7
            let remainder = span % 7
            var count = fullWeeks * days.count
            let anchorWeekday = calendar.component(.weekday, from: anchorDay)
            for offset in 0..<remainder {
                let wd = ((anchorWeekday - 1 + offset) % 7) + 1
                if let weekday = Weekday(rawValue: wd), days.contains(weekday) { count += 1 }
            }
            return count - 1
        case .dayOfMonth:
            guard let firstMonth = firstMonthStart(frequency: frequency, anchorDay: anchorDay) else { return nil }
            let dayMonth = calendar.startOfPeriod(.month, containing: day)
            let months = calendar.dateComponents([.month], from: firstMonth, to: dayMonth).month ?? 0
            return months >= 0 ? months : nil
        case .quota(_, let period):
            let anchorPeriod = calendar.startOfPeriod(period, containing: anchorDay)
            let dayPeriod = calendar.startOfPeriod(period, containing: day)
            let unit: Calendar.Component = period == .week ? .weekOfYear : .month
            let count = calendar.dateComponents([unit], from: anchorPeriod, to: dayPeriod).value(for: unit) ?? 0
            return count >= 0 ? count : nil
        }
    }

    /// Start of the month holding the first `dayOfMonth` occurrence at or after
    /// the anchor.
    private func firstMonthStart(frequency: Frequency, anchorDay: Date) -> Date? {
        guard case .dayOfMonth(let wanted) = frequency else { return nil }
        let monthStart = calendar.startOfPeriod(.month, containing: anchorDay)
        let last = calendar.lastDayOfMonth(containing: anchorDay)
        let effective = min(max(wanted, 1), last)
        if calendar.component(.day, from: anchorDay) <= effective {
            return monthStart
        }
        return calendar.date(byAdding: .month, value: 1, to: monthStart)
    }

    private func withinEnd(_ end: RecurrenceEnd, ordinal: Int, day: Date) -> Bool {
        switch end {
        case .never:
            return true
        case .until(let limit):
            return calendar.startOfDay(for: day) <= calendar.startOfDay(for: limit)
        case .afterOccurrences(let count):
            return ordinal < max(count, 0)
        }
    }

    // MARK: - Quota

    private func quotaOccurrences(
        for item: ItemSnapshot,
        count: Int,
        period: QuotaPeriod,
        in range: Range<Date>
    ) -> [GeneratedOccurrence] {
        guard count > 0 else { return [] }
        let anchorDay = calendar.startOfDay(for: item.settings.recurrence.anchorDate)
        var result: [GeneratedOccurrence] = []
        var cursor = calendar.startOfPeriod(period, containing: range.lowerBound)
        var guardCounter = 0

        while cursor < range.upperBound && guardCounter < 600 {
            guardCounter += 1
            let end = calendar.endOfPeriod(period, containing: cursor)
            defer { cursor = end }

            guard end > anchorDay else { continue }
            let slot = max(cursor, calendar.startOfDay(for: anchorDay))
            guard let ordinal = ordinal(
                of: cursor,
                frequency: item.settings.recurrence.frequency,
                anchorDay: anchorDay
            ) else { continue }
            guard withinEnd(item.settings.recurrence.end, ordinal: ordinal, day: cursor) else { break }

            result.append(
                GeneratedOccurrence(
                    key: OccurrenceKey(itemID: item.id, slot: calendar.startOfDay(for: slot)),
                    triggerDate: nil,
                    ordinal: ordinal,
                    quotaPeriod: DateInterval(start: cursor, end: end)
                )
            )
        }
        return result
    }
}
