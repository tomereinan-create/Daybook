import ActivityKit
import Foundation

/// What the lock screen card shows.
///
/// The split here is the whole privacy design of the push updater. `attributes`
/// are fixed when the app starts the activity and are **never transmitted
/// again** — so the day's items live there, on the device. `ContentState` is
/// what travels on every push, so it is an index and two counts. A server can
/// move the card to the next item without ever learning what any item is
/// called.
///
/// The cost of that split: the items are frozen for the activity's life, so
/// something added mid-day reaches the card when the app next restarts the
/// activity rather than instantly. The app restarts it on launch, on
/// foreground and on background refresh, and the controller also restarts it
/// whenever the day's items no longer match.
nonisolated struct DaybookActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Which of `attributes.items` is the current one. Out of range means
        /// the day is finished.
        var currentIndex: Int
        var doneCount: Int
        var totalCount: Int
    }

    /// Which day this card belongs to. The app starts a fresh one after
    /// midnight rather than updating across the boundary.
    var day: Date

    /// The day's items in order, captured when the activity started. Never
    /// leaves the device.
    var items: [LiveItem]
}

nonisolated extension DaybookActivityAttributes.ContentState {
    /// Where the card should be at a given moment.
    ///
    /// The current item is the last one whose moment has arrived; before the
    /// day starts that is the first item. Pure, so the index the server will
    /// send and the index the app computes are provably the same rule.
    static func at(
        _ now: Date,
        items: [LiveItem],
        doneCount: Int,
        totalCount: Int
    ) -> DaybookActivityAttributes.ContentState {
        let index = items.lastIndex { item in
            guard let trigger = item.triggerDate else { return false }
            return trigger <= now
        } ?? 0
        return DaybookActivityAttributes.ContentState(
            currentIndex: index,
            doneCount: doneCount,
            totalCount: totalCount
        )
    }
}

nonisolated extension DaybookActivityAttributes {
    /// The item the card should lead with, or `nil` when the day is done.
    func current(at state: ContentState) -> LiveItem? {
        items.indices.contains(state.currentIndex) ? items[state.currentIndex] : nil
    }

    /// What comes after it.
    func upcoming(at state: ContentState, limit: Int = 3) -> [LiveItem] {
        let next = state.currentIndex + 1
        guard next < items.count else { return [] }
        return Array(items[next...].prefix(limit))
    }
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

/// The times at which the card should move on, and where to.
///
/// This is everything the push server is told: when, and which index. No
/// titles, no notes, no identifiers beyond an opaque push token.
nonisolated struct PushSchedule: Codable, Sendable, Hashable {
    nonisolated struct Step: Codable, Sendable, Hashable {
        /// Seconds since 1970, so the server needs no date library.
        var at: Double
        var index: Int
        var doneCount: Int
        var totalCount: Int
    }

    var steps: [Step]

    /// Built from the same ordered items the attributes carry, so the indices
    /// the server sends always line up with what the card holds.
    static func from(items: [LiveItem], doneCount: Int, totalCount: Int, after now: Date) -> PushSchedule {
        var steps: [Step] = []
        for (index, item) in items.enumerated() {
            guard let trigger = item.triggerDate, trigger > now else { continue }
            steps.append(
                Step(
                    at: trigger.timeIntervalSince1970,
                    index: index,
                    doneCount: doneCount,
                    totalCount: totalCount
                )
            )
        }
        return PushSchedule(steps: steps)
    }
}
