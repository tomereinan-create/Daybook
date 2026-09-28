import Foundation
@testable import Daybook

/// Fixtures shared by the engine tests. Everything is explicit: no `Date()`,
/// no `Calendar.current`, no system time zone.
enum Fixture {
    static func calendar(
        timeZone: String = "UTC",
        firstWeekday: Int = 1,
        identifier: Calendar.Identifier = .gregorian
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            fatalError("Fixture produced an impossible date: \(year)-\(month)-\(day) \(hour):\(minute)")
        }
        return date
    }

    static func item(
        id: UUID = UUID(),
        title: String = "Item",
        preset: PresetKind = .task,
        settings: ItemSettings,
        createdAt: Date
    ) -> ItemSnapshot {
        ItemSnapshot(
            id: id,
            title: title,
            preset: preset,
            settings: settings,
            createdAt: createdAt
        )
    }

    /// A daily item at a fixed wall-clock time, staying until marked done.
    static func dailyItem(
        at time: TimeOfDay,
        from anchor: Date,
        title: String = "Daily",
        endCondition: EndCondition = .markedDone,
        onMissed: MissedPolicy = .logMissed,
        leadTime: TimeInterval = 0
    ) -> ItemSnapshot {
        var settings = ItemSettings.default
        settings.trigger = .daily(at: time)
        settings.recurrence = Recurrence(frequency: .daily, end: .never, anchorDate: anchor)
        settings.visibility = Visibility(leadTime: leadTime, surfaces: .all)
        settings.dismissal = Dismissal(endCondition: endCondition, onMissed: onMissed)
        return item(title: title, preset: .recurringTask, settings: settings, createdAt: anchor)
    }

    static func records(_ list: [OccurrenceStateRecord]) -> [OccurrenceKey: OccurrenceStateRecord] {
        Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
