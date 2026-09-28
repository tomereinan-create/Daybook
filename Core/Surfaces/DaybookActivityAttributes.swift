import ActivityKit
import Foundation

/// What the lock screen card shows.
///
/// `ContentState` has a 4 KB ceiling and is re-encoded on every update, so it
/// carries the smallest description of the day that the card can draw from —
/// already-formatted strings, not model objects.
nonisolated struct DaybookActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The thing to do now. `nil` when the day is clear but the card is
        /// still up.
        var current: LiveItem?
        /// The next few, in order. Capped by the engine.
        var upcoming: [LiveItem]
        var doneCount: Int
        var totalCount: Int

        var isClear: Bool { current == nil && upcoming.isEmpty }
    }

    /// Which day this card belongs to. Static for the activity's life, which is
    /// how the app knows to end it and start a fresh one after midnight.
    var day: Date
}

/// One line on the card.
nonisolated struct LiveItem: Codable, Hashable, Sendable, Identifiable {
    var itemID: String
    var slot: Double
    var title: String
    /// Step of a routine, quota counter, or why it is late. Already localized.
    var subtitle: String?
    /// The instant it fires, for a live countdown. `nil` for undated items.
    var triggerDate: Date?
    /// When it stops being relevant, for an in-progress countdown.
    var windowEnd: Date?
    var stateRaw: String
    var isMandatory: Bool
    var snoozeMinutes: Int?

    var id: String { "\(itemID)-\(slot)" }
    var state: OccurrenceState { OccurrenceState(rawValue: stateRaw) ?? .visible }
    var reference: OccurrenceReference { OccurrenceReference(itemID: itemID, slot: slot) }
    var allowsSnooze: Bool { snoozeMinutes != nil }
}

nonisolated extension LiveItem {
    init(_ occurrence: ResolvedOccurrence) {
        self.itemID = occurrence.key.itemID.uuidString
        self.slot = occurrence.key.slot.timeIntervalSince1970
        self.title = occurrence.displayTitle
        self.triggerDate = occurrence.effectiveTrigger
        self.windowEnd = occurrence.windowEnd
        self.stateRaw = occurrence.state.rawValue
        self.isMandatory = occurrence.item.settings.priority == .mandatory
        let alerting = occurrence.item.settings.alerting
        self.snoozeMinutes = alerting.snoozeAllowed ? alerting.snoozeMinutes : nil

        if let quota = occurrence.quotaProgress {
            self.subtitle = "\(quota.completed)/\(quota.target)"
        } else if occurrence.currentStep != nil {
            self.subtitle = occurrence.item.title
        } else {
            self.subtitle = nil
        }
    }
}
