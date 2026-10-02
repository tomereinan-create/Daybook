import AppIntents
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
        doneCount: 4,
        totalCount: 10,
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
    /// Behind on a quota habit. Drawn in the late colour.
    var isBehindPace: Bool = false
    /// When it fires, after snoozing and relative starts.
    var trigger: Date? = nil
    /// A running timer, from when it was started to when it fires.
    var countdown: ClosedRange<Date>? = nil
    /// `nil` when the item does not allow snoozing, so no button is drawn.
    var snoozeMinutes: Int? = nil

    var id: String { "\(reference.itemID)-\(reference.slot)" }

    static func == (lhs: WidgetRow, rhs: WidgetRow) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(state)
    }

    /// The day from the design prototype. Shown in the widget gallery, which
    /// must never show a real person's day.
    static let placeholders: [WidgetRow] = {
        let now = Date.now
        let calendar = Calendar.current
        func at(_ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        }
        func row(
            _ slot: Double,
            _ title: String,
            state: OccurrenceState = .visible,
            trigger: Date? = nil,
            trailing: String? = nil,
            quota: (done: Int, target: Int)? = nil,
            isBehindPace: Bool = false,
            countdown: ClosedRange<Date>? = nil
        ) -> WidgetRow {
            WidgetRow(
                reference: OccurrenceReference(itemID: UUID().uuidString, slot: slot),
                title: title,
                detail: nil,
                trailing: trailing ?? trigger.map { $0.formatted(date: .omitted, time: .shortened) },
                state: state,
                isMandatory: false,
                canStart: false,
                quota: quota,
                isBehindPace: isBehindPace,
                trigger: trigger,
                countdown: countdown,
                snoozeMinutes: 15
            )
        }
        return [
            row(0, "Call the dentist", state: .due, trigger: at(10)),
            row(1, "Take vitamins", state: .overdue, trigger: at(8)),
            row(2, "Laundry", state: .active, trigger: now.addingTimeInterval(1_421),
                countdown: now.addingTimeInterval(-1_279)...now.addingTimeInterval(1_421)),
            row(3, "Team stand-up", trigger: at(11)),
            row(4, "Pick up the parcel", trailing: "Post office"),
            row(5, "Pay the electricity bill", trigger: at(18)),
            row(6, "Gym", quota: (1, 3), isBehindPace: true),
            row(7, "Read", quota: (4, 5)),
        ]
    }()
}

/// The widget takes no options yet. It exists because AppIntentTimelineProvider
/// is the form of the protocol whose requirements are genuinely `async` —
/// TimelineProvider's async methods are convenience wrappers around a
/// completion handler that is not Sendable, so it cannot reach the store.
struct TodayWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.today.name"
    static let description = IntentDescription("widget.today.description")
    init() {}
}

nonisolated struct TodayTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        .placeholder
    }

    func snapshot(for configuration: TodayWidgetConfiguration, in context: Context) async -> TodayEntry {
        // The gallery preview must never show a real person's day.
        if context.isPreview { return .placeholder }
        return await Self.entry(at: .now)
    }

    func timeline(for configuration: TodayWidgetConfiguration, in context: Context) async -> Timeline<TodayEntry> {
        let now = Date.now
        let first = await Self.entry(at: now)
        // Redraw when something actually changes rather than on a fixed tick:
        // the next trigger, the next window closing, or midnight.
        let refreshDates = await Self.refreshPoints(after: now)
        var entries = [first]
        for date in refreshDates {
            entries.append(await Self.entry(at: date))
        }
        let nextReload = refreshDates.first ?? now.addingTimeInterval(3600)
        return Timeline(entries: entries, policy: .after(nextReload))
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
        self.trigger = occurrence.effectiveTrigger
        if let started = occurrence.record.startedAt, let fires = occurrence.effectiveTrigger, started < fires {
            self.countdown = started...fires
        }
        let alerting = occurrence.item.settings.alerting
        self.snoozeMinutes = alerting.snoozeAllowed ? alerting.snoozeMinutes : nil
        self.isBehindPace = occurrence.quotaProgress?.isBehindPace ?? false
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
