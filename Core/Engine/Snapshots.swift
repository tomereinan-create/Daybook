import Foundation

/// A read-only, `Sendable` projection of a stored item.
///
/// The engine only ever sees snapshots. That keeps SwiftData, the main actor
/// and the widget process out of the scheduling logic, and lets every engine
/// test run without a model container.
nonisolated struct ItemSnapshot: Sendable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let notes: String
    let preset: PresetKind
    let settings: ItemSettings
    let isArchived: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        preset: PresetKind = .task,
        settings: ItemSettings,
        isArchived: Bool = false,
        createdAt: Date = .distantPast
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.preset = preset
        self.settings = settings
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

/// Identity of a single occurrence: which item, and which slot of its
/// recurrence. One-off and undated items use a single stable slot.
nonisolated struct OccurrenceKey: Sendable, Hashable, Codable {
    let itemID: UUID
    let slot: Date
}

/// Per-occurrence user state. Completion lives here, never on the item.
nonisolated struct OccurrenceStateRecord: Sendable, Hashable {
    var key: OccurrenceKey
    var completedAt: Date?
    var missedAt: Date?
    var snoozedUntil: Date?
    /// Set when the user starts a relative timer.
    var startedAt: Date?
    /// How far through a routine the user has got.
    var currentStepIndex: Int
    /// How many nags have already fired, used for escalation.
    var nagsFired: Int
    /// Quota habits only: how many times the user has done it this period.
    /// Everything else completes once and uses `completedAt`.
    var completionCount: Int
    /// What the user answered when they finished it, if it asked.
    var answer: String?
    /// When a hold started by Done runs out. Until then the item is being
    /// done rather than waiting to be.
    var holdUntil: Date?

    init(
        key: OccurrenceKey,
        completedAt: Date? = nil,
        missedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        startedAt: Date? = nil,
        currentStepIndex: Int = 0,
        nagsFired: Int = 0,
        completionCount: Int = 0,
        answer: String? = nil,
        holdUntil: Date? = nil
    ) {
        self.key = key
        self.completedAt = completedAt
        self.missedAt = missedAt
        self.snoozedUntil = snoozedUntil
        self.startedAt = startedAt
        self.currentStepIndex = currentStepIndex
        self.nagsFired = nagsFired
        self.completionCount = completionCount
        self.answer = answer
        self.holdUntil = holdUntil
    }
}

/// An occurrence the generator placed on the calendar, before user state is
/// taken into account.
nonisolated struct GeneratedOccurrence: Sendable, Hashable {
    let key: OccurrenceKey
    /// When it fires. `nil` for items with no calendar-bound trigger: undated
    /// tasks, quota habits, location reminders and unstarted relative timers.
    let triggerDate: Date?
    /// Zero-based ordinal within the recurrence, counted from the anchor.
    let ordinal: Int
    /// Only set for quota frequencies.
    let quotaPeriod: DateInterval?

    var itemID: UUID { key.itemID }
    var slot: Date { key.slot }
}

/// A generated occurrence plus its item, its user state, and the state the
/// engine resolved for a given moment. This is what every surface consumes.
nonisolated struct ResolvedOccurrence: Sendable, Hashable, Identifiable {
    let item: ItemSnapshot
    let generated: GeneratedOccurrence
    let record: OccurrenceStateRecord
    let state: OccurrenceState
    /// The trigger after snoozing and relative starts are applied. This is the
    /// instant alerts are hung off, not `generated.triggerDate`.
    let effectiveTrigger: Date?
    /// When it stops being shown, if it ever does.
    let windowEnd: Date?
    /// Quota progress, for flexible habits only.
    let quotaProgress: QuotaProgress?

    var id: OccurrenceKey { generated.key }
    var key: OccurrenceKey { generated.key }
    var title: String { item.title }

    /// The step a routine is currently on, if the item has steps.
    var currentStep: Step? {
        let steps = item.settings.steps
        guard !steps.isEmpty, record.currentStepIndex < steps.count else { return nil }
        return steps[record.currentStepIndex]
    }

    /// What a surface should print as the line of text.
    var displayTitle: String {
        currentStep.map { "\(item.title): \($0.title)" } ?? item.title
    }

    /// A copy in a different state. Used when the engine can see something one
    /// occurrence cannot see about itself, such as a newer occurrence of the
    /// same recurring item having arrived.
    func with(state newState: OccurrenceState) -> ResolvedOccurrence {
        ResolvedOccurrence(
            item: item,
            generated: generated,
            record: record,
            state: newState,
            effectiveTrigger: effectiveTrigger,
            windowEnd: windowEnd,
            quotaProgress: quotaProgress
        )
    }
}

nonisolated struct QuotaProgress: Sendable, Hashable {
    let completed: Int
    let target: Int
    let period: DateInterval
    /// True when the remaining completions no longer fit comfortably in the
    /// days left. See `QuotaPacer`.
    let isBehindPace: Bool

    var fractionComplete: Double {
        target > 0 ? Double(completed) / Double(target) : 0
    }
}
