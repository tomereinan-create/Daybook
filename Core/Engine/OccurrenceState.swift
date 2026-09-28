import Foundation

/// Where an occurrence stands right now.
enum OccurrenceState: String, Sendable, Hashable, CaseIterable {
    /// Exists, but too early to show anywhere.
    case upcoming
    /// Inside its lead time, or undated and simply outstanding.
    case visible
    /// Running: a time block in progress, or a routine part-way through.
    case active
    /// Trigger has passed within the grace period.
    case due
    /// Trigger has passed, grace is gone, and it still wants action.
    case overdue
    /// Snoozed into the future.
    case snoozed
    case done
    /// Its window closed without completion.
    case missed

    /// States that mean the user still has something to do.
    var isOutstanding: Bool {
        switch self {
        case .upcoming, .visible, .active, .due, .overdue, .snoozed: true
        case .done, .missed: false
        }
    }

    /// States a live surface (lock screen card, home widget) prints.
    var appearsOnLiveSurfaces: Bool {
        switch self {
        case .visible, .active, .due, .overdue: true
        case .upcoming, .snoozed, .done, .missed: false
        }
    }

    /// Lower sorts first.
    var sortRank: Int {
        switch self {
        case .overdue: 0
        case .due: 1
        case .active: 2
        case .visible: 3
        case .snoozed: 4
        case .upcoming: 5
        case .done: 6
        case .missed: 7
        }
    }
}

/// How the Today screen groups the day.
enum DaySection: String, Sendable, Hashable, CaseIterable {
    case now
    case upcoming
    case undated
    case done
    case missed
}
