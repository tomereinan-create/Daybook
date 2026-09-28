import Foundation

enum EndCondition: Codable, Sendable, Hashable {
    /// Stays on screen until the user completes it.
    case markedDone
    /// Disappears the moment the trigger time arrives (an event has begun).
    case eventStart
    /// Stays for a fixed duration after the trigger, then goes.
    case windowEnds(TimeInterval)
    /// Stays until a wall-clock time on the occurrence's day.
    case atTime(TimeOfDay)
    /// Never leaves on its own.
    case manualOnly
}

enum MissedPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    /// Disappears and is recorded as missed.
    case logMissed
    /// Reappears on the next day at the same time.
    case rollOver
    /// Loses its schedule and becomes an open task that stays until done.
    case becomeOpenTask
}

struct Dismissal: Codable, Sendable, Hashable {
    var endCondition: EndCondition
    var onMissed: MissedPolicy

    static let untilDone = Dismissal(endCondition: .markedDone, onMissed: .becomeOpenTask)
    static let atEventStart = Dismissal(endCondition: .eventStart, onMissed: .logMissed)
}
