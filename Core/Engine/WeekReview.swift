import Foundation

/// What the weekly review screen shows.
///
/// The review is the only place Someday items surface and the only place a
/// Waiting-for item is chased, so this is also the answer to "where did the
/// things I hid from myself go".
nonisolated struct WeekReview: Sendable {
    let week: DateInterval
    let completed: Int
    /// Windows that closed unfinished. Events that simply started are not
    /// counted: nothing was owed.
    let missed: Int
    /// Habits that will not hit their quota at the current rate.
    let behind: [ResolvedOccurrence]
    /// Things someone else owes you, oldest silence first.
    let waiting: [WaitingItem]
    /// Out of sight all week; this is where they come back.
    let someday: [ItemSnapshot]

    var hasAnythingToSay: Bool {
        completed > 0 || missed > 0 || !behind.isEmpty || !waiting.isEmpty || !someday.isEmpty
    }
}

nonisolated struct WaitingItem: Sendable, Identifiable {
    let item: ItemSnapshot
    /// Days since anything about it changed.
    let daysQuiet: Int
    /// True once it has been quiet longer than its own follow-up interval.
    let isOverdue: Bool

    var id: UUID { item.id }
}

nonisolated extension ScheduleEngine {
    func weekReview(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> WeekReview {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 24 * 3600)

        let resolved = resolve(
            items: items,
            records: records,
            in: week.start..<max(week.end, now),
            now: now
        )

        let completed = resolved.count { $0.state == .done }
        let missed = resolved.count { $0.state == .missed && !$0.concludedNaturally }
        let behind = resolved.filter { $0.quotaProgress?.isBehindPace == true }

        let waiting = items
            .filter { $0.preset == .waitingFor && !$0.isArchived }
            .map { item -> WaitingItem in
                let days = max(calendar.dayCount(from: item.createdAt, to: now), 0)
                let interval = item.settings.alerting.nag
                let threshold = interval.isEnabled ? max(interval.intervalMinutes / (24 * 60), 1) : 3
                return WaitingItem(item: item, daysQuiet: days, isOverdue: days >= threshold)
            }
            .sorted { $0.daysQuiet > $1.daysQuiet }

        let someday = items
            .filter { $0.preset == .someday && !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }

        return WeekReview(
            week: week,
            completed: completed,
            missed: missed,
            behind: behind,
            waiting: waiting,
            someday: someday
        )
    }
}
