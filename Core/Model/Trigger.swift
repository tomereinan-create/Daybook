import Foundation

nonisolated enum TriggerKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Fires at a date-time (one-off) or at `timeOfDay` on each recurrence day.
    case time
    /// Fires `relativeMinutes` after the user starts the occurrence.
    case relative
    /// Fires on entering or leaving a region.
    case location
    /// Fires when the previous step of a routine is completed.
    case afterPrevious
    /// Never fires. The item simply exists until it is done.
    case none
}

nonisolated enum LocationEdge: String, Codable, Sendable, Hashable, CaseIterable {
    case arrive
    case leave
}

nonisolated struct LocationTrigger: Codable, Sendable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    /// Metres. CoreLocation clamps this to the device maximum.
    var radius: Double
    var edge: LocationEdge
}

nonisolated struct Trigger: Codable, Sendable, Hashable {
    var kind: TriggerKind

    /// Used when `kind == .time` and the recurrence is `.once`.
    var date: Date?
    /// Used when `kind == .time` and the item recurs.
    var timeOfDay: TimeOfDay?
    /// Used when `kind == .relative`.
    var relativeMinutes: Int?
    /// Used when `kind == .location`.
    var location: LocationTrigger?

    static let none = Trigger(kind: .none)

    static func at(_ date: Date) -> Trigger {
        Trigger(kind: .time, date: date)
    }

    static func daily(at timeOfDay: TimeOfDay) -> Trigger {
        Trigger(kind: .time, timeOfDay: timeOfDay)
    }

    static func minutesAfterStart(_ minutes: Int) -> Trigger {
        Trigger(kind: .relative, relativeMinutes: minutes)
    }

    /// True when the engine can place this trigger on a calendar without
    /// waiting for the user to start it or to walk somewhere.
    var isCalendarBound: Bool {
        kind == .time && (date != nil || timeOfDay != nil)
    }
}
