import Foundation

/// Decides whether a flexible habit has fallen behind.
///
/// The rule, stated the way it would be explained to a person: *you are behind
/// when the number of times still owed is at least the number of days left*, so
/// "3 times a week" only nudges on Friday if you have done fewer than one.
/// It never nudges on the first day of a period, and it never nudges once the
/// quota is met.
nonisolated struct QuotaPacer: Sendable {
    var calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func progress(
        target: Int,
        completionsInPeriod: Int,
        period: DateInterval,
        now: Date
    ) -> QuotaProgress {
        let remaining = max(target - completionsInPeriod, 0)
        let daysLeft = max(daysRemaining(in: period, at: now), 0)
        let behind = remaining > 0 && daysLeft > 0 && remaining >= daysLeft
        return QuotaProgress(
            completed: completionsInPeriod,
            target: target,
            period: period,
            isBehindPace: behind
        )
    }

    /// Days left in the period counting today, so the last day of a week
    /// reports 1, not 0.
    func daysRemaining(in period: DateInterval, at now: Date) -> Int {
        guard now < period.end else { return 0 }
        let today = calendar.startOfDay(for: max(now, period.start))
        let lastDay = calendar.startOfDay(for: period.end.addingTimeInterval(-1))
        return calendar.dayCount(from: today, to: lastDay) + 1
    }
}
