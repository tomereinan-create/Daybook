import Foundation

extension Calendar {
    /// The given wall-clock time on the given day.
    ///
    /// On a spring-forward day a time that does not exist (02:30 where the
    /// clocks jump 02:00 to 03:00) is snapped forward by Foundation, which is
    /// the behaviour we want: the item still fires once, slightly later.
    func date(setting time: TimeOfDay, on day: Date) -> Date? {
        var components = dateComponents([.era, .year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        components.nanosecond = 0
        return date(from: components)
    }

    func startOfNextDay(after date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    func endOfDay(for date: Date) -> Date {
        self.date(setting: TimeOfDay(hour: 23, minute: 59), on: date) ?? date
    }

    func nextHour(after date: Date) -> Date {
        let next = self.date(byAdding: .hour, value: 1, to: date) ?? date.addingTimeInterval(3600)
        var components = dateComponents([.era, .year, .month, .day, .hour], from: next)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return self.date(from: components) ?? next
    }

    /// Whole calendar days between the starts of two days. Negative when `to`
    /// precedes `from`. Counting days rather than seconds keeps DST out of it.
    func dayCount(from: Date, to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }

    func weekday(of date: Date) -> Weekday {
        Weekday(rawValue: component(.weekday, from: date)) ?? .sunday
    }

    /// Start of the week (respecting `firstWeekday`) or of the month.
    func startOfPeriod(_ period: QuotaPeriod, containing date: Date) -> Date {
        let unit: Calendar.Component = period == .week ? .weekOfYear : .month
        return dateInterval(of: unit, for: date)?.start ?? startOfDay(for: date)
    }

    func endOfPeriod(_ period: QuotaPeriod, containing date: Date) -> Date {
        let unit: Calendar.Component = period == .week ? .weekOfYear : .month
        return dateInterval(of: unit, for: date)?.end ?? startOfNextDay(after: date)
    }

    func timeOfDay(of date: Date) -> TimeOfDay {
        let c = dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    /// The last valid day number in the month containing `date`.
    func lastDayOfMonth(containing date: Date) -> Int {
        range(of: .day, in: .month, for: date)?.upperBound.advanced(by: -1) ?? 28
    }
}
