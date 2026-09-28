import Foundation
import WidgetKit

/// One rendered moment of the day.
nonisolated struct TodayEntry: TimelineEntry, Sendable {
    let date: Date
    let rows: [WidgetRow]
    let doneCount: Int
    let totalCount: Int
    /// Set when the store could not be opened — the widget says so rather than
    /// drawing a convincing but empty day.
    let isUnavailable: Bool

    var progress: Double {
        totalCount > 0 ? Double(doneCount) / Double(totalCount) : 0
    }

    static let placeholder = TodayEntry(
        date: .now,
        rows: WidgetRow.placeholders,
        doneCount: 2,
        totalCount: 11,
        isUnavailable: false
    )

    static func unavailable(at date: Date) -> TodayEntry {
        TodayEntry(date: date, rows: [], doneCount: 0, totalCount: 0, isUnavailable: true)
    }
}

/// A row as the widget draws it. Flattened from `ResolvedOccurrence` so the
/// view has no decisions left to make and the entry stays `Sendable`.
nonisolated struct WidgetRow: Sendable, Hashable, Identifiable {
    let reference: OccurrenceReference
    let title: String
    let detail: String?
    let trailing: String?
    let state: OccurrenceState
    let isMandatory: Bool
    let canStart: Bool
    let quota: (done: Int, target: Int)?

    var id: String { "\(reference.itemID)-\(reference.slot)" }

    static func == (lhs: WidgetRow, rhs: WidgetRow) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(state)
    }

    static let placeholders: [WidgetRow] = [
        WidgetRow(
            reference: OccurrenceReference(itemID: UUID().uuidString, slot: 0),
            title: "Take your pills",
            detail: "Morning routine · step 2 of 4",
            trailing: nil,
            state: .due,
            isMandatory: false,
            canStart: false,
            quota: nil
        ),
        WidgetRow(
            reference: OccurrenceReference(itemID: UUID().uuidString, slot: 1),
            title: "Leave for the dentist",
            detail: nil,
            trailing: "08:30",
            state: .visible,
            isMandatory: false,
            canStart: false,
            quota: nil
        )
    ]
}

nonisolated struct TodayTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // The gallery preview must never show a real person's day.
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await Self.entry(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let now = Date.now
            let first = await Self.entry(at: now)
            // Redraw when something actually changes rather than on a fixed
            // tick: the next trigger, the next window closing, or midnight.
            let refreshDates = await Self.refreshPoints(after: now)
            var entries = [first]
            for date in refreshDates {
                entries.append(await Self.entry(at: date))
            }
            let nextReload = refreshDates.first ?? now.addingTimeInterval(3600)
            completion(Timeline(entries: entries, policy: .after(nextReload)))
        }
    }

    @MainActor
    private static func entry(at date: Date) -> TodayEntry {
        let store = SharedStore.current
        guard !store.isUsingFallbackStore else {
            return .unavailable(at: date)
        }
        let rows = SurfaceData
            .entries(for: .homeWidget, now: date)
            .map(WidgetRow.init)
        let progress = SurfaceData.progress(now: date)
        return TodayEntry(
            date: date,
            rows: rows,
            doneCount: progress.done,
            totalCount: progress.total,
            isUnavailable: false
        )
    }

    /// The next few instants at which the day looks different. Capped, because
    /// WidgetKit budgets refreshes and a timeline of fifty entries spends that
    /// budget on moments nobody will see.
    @MainActor
    private static func refreshPoints(after now: Date) -> [Date] {
        let calendar = Calendar.current
        let live = SurfaceData.entries(for: .homeWidget, now: now)
        var points: Set<Date> = [calendar.startOfNextDay(after: now)]

        for occurrence in live {
            if let trigger = occurrence.effectiveTrigger, trigger > now {
                points.insert(trigger)
            }
            if let end = occurrence.windowEnd, end > now {
                points.insert(end)
            }
        }
        return points.sorted().prefix(4).map { $0 }
    }
}

nonisolated extension WidgetRow {
    init(_ occurrence: ResolvedOccurrence) {
        self.reference = OccurrenceReference(occurrence.key)
        self.title = occurrence.displayTitle
        self.isMandatory = occurrence.item.settings.priority == .mandatory
        self.state = occurrence.state
        self.canStart = occurrence.item.settings.trigger.kind == .relative
            && occurrence.record.startedAt == nil
        if let quota = occurrence.quotaProgress {
            self.quota = (quota.completed, quota.target)
            self.detail = quota.isBehindPace ? String(localized: "label.behindPace") : nil
            self.trailing = nil
        } else {
            self.quota = nil
            self.detail = occurrence.currentStep.map { _ in occurrence.item.title }
            self.trailing = occurrence.effectiveTrigger.map {
                $0.formatted(date: .omitted, time: .shortened)
            }
        }
    }
}
