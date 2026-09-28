import Foundation

/// A wall-clock time with no date attached. Recurring items carry one of these
/// instead of an absolute `Date`, so "07:30 every day" survives DST and travel.
nonisolated struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    var minutesFromMidnight: Int { hour * 60 + minute }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

/// 1 = Sunday, matching `Calendar.component(.weekday:)`.
nonisolated enum Weekday: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum Priority: String, Codable, Sendable, Hashable, CaseIterable {
    case normal
    /// Reserved for the Screen Time / FamilyControls blocking that is out of
    /// scope for v1. Today it only affects ordering and notification budget.
    case mandatory
}

nonisolated enum QuietHoursPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case respect
    case override
}

/// One ordered sub-step of a routine.
nonisolated struct Step: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

/// The user's global do-not-disturb band. Stored in app settings, not per item.
nonisolated struct QuietHours: Codable, Sendable, Hashable {
    var isEnabled: Bool
    var start: TimeOfDay
    var end: TimeOfDay

    static let `default` = QuietHours(
        isEnabled: true,
        start: TimeOfDay(hour: 22, minute: 30),
        end: TimeOfDay(hour: 7, minute: 0)
    )

    /// True when `time` falls inside the band, handling bands that wrap midnight.
    func contains(_ time: TimeOfDay) -> Bool {
        guard isEnabled else { return false }
        let t = time.minutesFromMidnight
        let s = start.minutesFromMidnight
        let e = end.minutesFromMidnight
        if s == e { return false }
        return s < e ? (t >= s && t < e) : (t >= s || t < e)
    }
}
