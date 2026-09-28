import ActivityKit
import Foundation

/// Runs the day's lock screen card.
///
/// One activity at a time, for one day. `refresh` is the only entry point and
/// decides by itself whether to start, update, restart or end — so launch,
/// background refresh, a completion and the wake-up alarm can all just call it.
///
/// Three platform facts shape this. The system kills an activity after about
/// eight hours, so one started at breakfast is gone by mid-afternoon unless it
/// is replaced. `attributes` never travel after the activity starts, which is
/// why the day's items live there and the push carries only an index. And a
/// push token arrives asynchronously, some time after the request, so it is
/// observed rather than waited for.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Restart well before the system's own limit rather than at it, so the
    /// card is never briefly absent.
    private let maximumAge: TimeInterval = 7 * 3600

    private var startedAt: Date?
    private var tokenObservation: Task<Void, Never>?

    /// Set by the app when push updates are switched on. Given the token and
    /// the schedule; never given any item's content.
    var uploadRegistration: (@MainActor (PushRegistration) async -> Void)?

    private init() {}

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var running: Activity<DaybookActivityAttributes>? {
        Activity<DaybookActivityAttributes>.activities.first
    }

    /// Bring the card into line with the day. Safe to call as often as you like.
    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard areActivitiesEnabled else { return }

        let items = Self.todaysItems(now: now)
        let progress = SurfaceData.progress(now: now)
        let today = calendar.startOfDay(for: now)

        guard let running else {
            guard !items.isEmpty else { return }
            await start(day: today, items: items, progress: progress, now: now)
            return
        }

        if items.isEmpty {
            await end()
            return
        }

        // The attributes are frozen, so any change to the day's shape means the
        // card is holding a list that no longer matches and has to be replaced.
        let itemsChanged = running.attributes.items != items
        let isStale = running.attributes.day != today
            || itemsChanged
            || (startedAt.map { now.timeIntervalSince($0) > maximumAge } ?? false)

        if isStale {
            await end()
            await start(day: today, items: items, progress: progress, now: now)
            return
        }

        let state = Self.contentState(items: items, progress: progress, now: now)
        await Self.updateRunning(content(state, items: items, now: now))
    }

    /// Ends the card outright.
    func end() async {
        tokenObservation?.cancel()
        tokenObservation = nil
        await Self.endAll()
        startedAt = nil
    }

    // MARK: - Content

    /// The day's items, in the order the card will step through them.
    static func todaysItems(now: Date = .now) -> [LiveItem] {
        SurfaceData.entries(for: .liveActivity, now: now).map(LiveItem.init)
    }

    /// The only thing a push carries. Numbers, and nothing else.
    static func contentState(
        items: [LiveItem],
        progress: (done: Int, total: Int),
        now: Date
    ) -> DaybookActivityAttributes.ContentState {
        .at(now, items: items, doneCount: progress.done, totalCount: progress.total)
    }

    private func content(
        _ state: DaybookActivityAttributes.ContentState,
        items: [LiveItem],
        now: Date
    ) -> ActivityContent<DaybookActivityAttributes.ContentState> {
        // Go visibly stale rather than keep showing a day that has moved on.
        // The next moment is the first at which this card could be wrong.
        let nextChange = items
            .compactMap(\.triggerDate)
            .first { $0 > now }
        let stale = nextChange.map { max($0, now.addingTimeInterval(60)) }
            ?? now.addingTimeInterval(3600)
        return ActivityContent(state: state, staleDate: stale)
    }

    private func start(
        day: Date,
        items: [LiveItem],
        progress: (done: Int, total: Int),
        now: Date
    ) async {
        let state = Self.contentState(items: items, progress: progress, now: now)
        do {
            let activity = try Activity.request(
                attributes: DaybookActivityAttributes(day: day, items: items),
                content: content(state, items: items, now: now),
                // A token means a server can move the card on while the app is
                // closed. Without an upload handler nothing is ever sent, and
                // the token simply goes unused.
                pushType: uploadRegistration == nil ? nil : .token
            )
            startedAt = now
            if uploadRegistration != nil {
                observeToken(of: activity, items: items, progress: progress, now: now)
            }
        } catch {
            // Refused when the user has switched Live Activities off, or when
            // too many are already running. Neither is worth interrupting them
            // about: every other surface still works.
            startedAt = nil
        }
    }

    /// The push token is not available at request time; it arrives shortly
    /// after, and can be reissued. Each one is uploaded with the schedule it
    /// belongs to.
    private func observeToken(
        of activity: Activity<DaybookActivityAttributes>,
        items: [LiveItem],
        progress: (done: Int, total: Int),
        now: Date
    ) {
        tokenObservation?.cancel()
        let schedule = PushSchedule.from(
            items: items,
            doneCount: progress.done,
            totalCount: progress.total,
            after: now
        )
        tokenObservation = Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = data.map { String(format: "%02x", $0) }.joined()
                await self?.uploadRegistration?(
                    PushRegistration(token: token, schedule: schedule)
                )
            }
        }
    }

    // MARK: - Crossing into ActivityKit
    //
    // `Activity` cannot be carried from the main actor into ActivityKit's
    // nonisolated async methods, so these fetch it and use it in the same
    // nonisolated context.

    private nonisolated static func endAll() async {
        for activity in Activity<DaybookActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func updateRunning(
        _ content: ActivityContent<DaybookActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<DaybookActivityAttributes>.activities.first else { return }
        await activity.update(content)
    }
}

/// Everything the push server is ever told.
nonisolated struct PushRegistration: Codable, Sendable, Hashable {
    var token: String
    var schedule: PushSchedule
}
