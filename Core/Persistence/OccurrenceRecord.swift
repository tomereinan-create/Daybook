import Foundation
import SwiftData

/// Per-occurrence user state. One row per (item, slot), created lazily the
/// first time the user touches an occurrence.
@Model
final class OccurrenceRecord {
    #Unique<OccurrenceRecord>([\.itemID, \.slot])

    var itemID: UUID = UUID()
    var slot: Date = Date.distantPast
    var completedAt: Date?
    var missedAt: Date?
    var snoozedUntil: Date?
    var startedAt: Date?
    var currentStepIndex: Int = 0
    var nagsFired: Int = 0
    var completionCount: Int = 0

    init(key: OccurrenceKey) {
        self.itemID = key.itemID
        self.slot = key.slot
    }

    var key: OccurrenceKey { OccurrenceKey(itemID: itemID, slot: slot) }

    var state: OccurrenceStateRecord {
        get {
            OccurrenceStateRecord(
                key: key,
                completedAt: completedAt,
                missedAt: missedAt,
                snoozedUntil: snoozedUntil,
                startedAt: startedAt,
                currentStepIndex: currentStepIndex,
                nagsFired: nagsFired,
                completionCount: completionCount
            )
        }
        set {
            itemID = newValue.key.itemID
            slot = newValue.key.slot
            completedAt = newValue.completedAt
            missedAt = newValue.missedAt
            snoozedUntil = newValue.snoozedUntil
            startedAt = newValue.startedAt
            currentStepIndex = newValue.currentStepIndex
            nagsFired = newValue.nagsFired
            completionCount = newValue.completionCount
        }
    }
}
