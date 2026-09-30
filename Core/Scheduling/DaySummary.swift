import Foundation

/// The day, held on the lock screen as one standing notification.
///
/// The lock-screen card and the home widget both live in an app extension,
/// and an install that cannot register one has neither. A notification needs
/// no extension and no shared container: the app posts it itself, it stays on
/// the lock screen until dismissed, and posting again under the same
/// identifier replaces it in place.
///
/// It is not a Live Activity and does not pretend to be. It does not tick, it
/// does not redraw itself between posts, and its Done button needs a long
/// press rather than a tap. What it does is put the day where the day is
/// supposed to be, on a build where nothing else can.
nonisolated struct DaySummary: Sendable, Hashable {
    /// Fixed, so each post replaces the last rather than stacking up.
    static let identifier = "daybook.today"

    var title: String
    var body: String
    /// The next thing due, so the notification's own Done button finishes
    /// something real instead of just opening the app.
    var next: OccurrenceKey?
    var nextSnoozeMinutes: Int?
}

nonisolated struct DaySummaryBuilder: Sendable {
    /// How many lines before the rest become a count. A lock screen shows
    /// about this much before it truncates, and a truncated list is worse
    /// than an honest "+4 more".
    var maximumLines = 6

    init() {}

    /// `nil` when there is nothing worth holding on the lock screen, which is
    /// the signal to take the existing one down.
    func summary(for plan: DayPlan, now: Date) -> DaySummary? {
        let outstanding = [DaySection.now, .upcoming, .undated].flatMap { plan[$0] }
        guard !outstanding.isEmpty else { return nil }

        let done = plan.completionCount
        let total = done + outstanding.count
        let title = String(localized: "summary.notification.title \(done) \(total)")

        let shown = outstanding.prefix(maximumLines)
        var lines = shown.map { line(for: $0, now: now) }
        let remaining = outstanding.count - shown.count
        if remaining > 0 {
            lines.append(String(localized: "summary.notification.more \(remaining)"))
        }

        // The first thing in `.now` is what a Done button should finish; if
        // nothing is due yet, the next thing coming up.
        let next = plan[.now].first ?? outstanding.first
        return DaySummary(
            title: title,
            body: lines.joined(separator: "\n"),
            next: next?.key,
            nextSnoozeMinutes: next.flatMap {
                let alerting = $0.item.settings.alerting
                return alerting.snoozeAllowed ? alerting.snoozeMinutes : nil
            }
        )
    }

    private func line(for occurrence: ResolvedOccurrence, now: Date) -> String {
        guard let trigger = occurrence.effectiveTrigger else {
            return occurrence.displayTitle
        }
        let time = trigger.formatted(date: .omitted, time: .shortened)
        return "\(time)  \(occurrence.displayTitle)"
    }
}
