import Foundation

enum QuotaPeriod: String, Codable, Sendable, Hashable, CaseIterable {
    case week
    case month
}

enum Frequency: Codable, Sendable, Hashable {
    case once
    case daily
    case weekdays(Set<Weekday>)
    case everyNDays(Int)
    /// Clamped to the last day of shorter months, so 31 means "month end" in February.
    case dayOfMonth(Int)
    /// N completions per period, with no fixed time. Pacing drives the nudges.
    case quota(count: Int, period: QuotaPeriod)

    var isQuota: Bool {
        if case .quota = self { return true }
        return false
    }

    var repeats: Bool {
        if case .once = self { return false }
        return true
    }
}

enum RecurrenceEnd: Codable, Sendable, Hashable {
    case never
    case until(Date)
    case afterOccurrences(Int)
}

struct Recurrence: Codable, Sendable, Hashable {
    var frequency: Frequency
    var end: RecurrenceEnd
    /// The day the recurrence counts from. `everyNDays` and `afterOccurrences`
    /// are both measured from here.
    var anchorDate: Date

    static func once(from anchor: Date = .distantPast) -> Recurrence {
        Recurrence(frequency: .once, end: .never, anchorDate: anchor)
    }

    static func daily(from anchor: Date) -> Recurrence {
        Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
    }
}
