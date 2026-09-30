import Foundation

/// The engine never calls `Date()`. Every time-dependent answer comes from a
/// clock handed in by the caller, which is what makes the tests deterministic.
nonisolated protocol Clock: Sendable {
    var now: Date { get }
}

nonisolated struct SystemClock: Clock {
    var now: Date { Date() }
    init() {}
}

/// A clock frozen at a fixed instant. Tests only.
nonisolated struct FixedClock: Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// Knobs the engine reads instead of hardcoding numbers, so the platform caps
/// can be tightened without touching logic.
nonisolated struct EngineConfiguration: Sendable, Hashable {
    /// iOS allows 64 pending local notifications per app. We keep headroom so
    /// an interactive snooze scheduled from the lock screen never gets refused.
    var notificationBudget: Int
    /// How far ahead the rolling scheduler plans, in seconds.
    var schedulingWindow: TimeInterval
    /// How far back the engine looks for occurrences that are still
    /// outstanding, so yesterday's unfinished task still shows up today.
    var outstandingLookback: TimeInterval
    /// How long after its trigger an occurrence still reads as "due" rather
    /// than "overdue".
    var dueGrace: TimeInterval
    /// Live Activities are killed by the system after about eight hours.
    var liveActivityMaxDuration: TimeInterval
    /// How many entries the engine hands each surface.
    var liveActivityEntryCount: Int
    var homeWidgetEntryCount: Int

    static let `default` = EngineConfiguration(
        notificationBudget: 60,
        schedulingWindow: 48 * 3600,
        outstandingLookback: 30 * 24 * 3600,
        dueGrace: 15 * 60,
        liveActivityMaxDuration: 8 * 3600,
        liveActivityEntryCount: 4,
        homeWidgetEntryCount: 12
    )
}
