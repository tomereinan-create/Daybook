import ActivityKit
import Foundation

/// Runs the day's lock screen card.
///
/// One activity at a time, for one day. `refresh` is the only entry point and
/// decides by itself whether to start, update, restart or end — so launch,
/// background refresh, a completion and the wake-up alarm can all just call it.
///
/// Two platform facts shape this. The system kills an activity after about
/// eight hours, so a card started at breakfast is gone by mid-afternoon unless
/// it is replaced. And `ContentState` is the only thing that travels on an
/// update, which is why the push updater in phase 4 can slot in without
/// restructuring: it sends the same value this builds locally.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Restart well before the system's own limit rather than at it, so the
    /// card is never briefly absent.
    private let maximumAge: TimeInterval = 7 * 3600

    private var startedAt: Date?

    private init() {}

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Which day the running card belongs to, if one is running.
    private var runningDay: Date? {
        Activity<DaybookActivityAttributes>.activities.first?.attributes.day
    }

    /// Bring the card into line with the day. Safe to call as often as you like.
    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard areActivitiesEnabled else { return }

        let state = Self.contentState(now: now)
        let today = calendar.startOfDay(for: now)

        guard let runningDay else {
            // Nothing running. Only start one if there is something to say.
            guard !state.isClear else { return }
            start(day: today, state: state, now: now)
            return
        }

        if state.isClear {
            await end()
            return
        }

        // A new day, or old enough that the system is about to end it anyway.
        let isStale = runningDay != today
            || (startedAt.map { now.timeIntervalSince($0) > maximumAge } ?? false)
        if isStale {
            await end()
            start(day: today, state: state, now: now)
            return
        }

        await Self.updateRunning(content(state, now: now))
    }

    /// Ends the card outright. Used when the last thing is done, and on the way
    /// out of a day.
    func end() async {
        await Self.endAll()
        startedAt = nil
    }

    // MARK: - Content

    /// The single place the card's contents are built. The push updater sends
    /// exactly this value.
    static func contentState(now: Date = .now) -> DaybookActivityAttributes.ContentState {
        let entries = SurfaceData.entries(for: .liveActivity, now: now)
        let items = entries.map(LiveItem.init)
        let progress = SurfaceData.progress(now: now)
        return DaybookActivityAttributes.ContentState(
            current: items.first,
            upcoming: Array(items.dropFirst()),
            doneCount: progress.done,
            totalCount: progress.total
        )
    }

    private func content(
        _ state: DaybookActivityAttributes.ContentState,
        now: Date
    ) -> ActivityContent<DaybookActivityAttributes.ContentState> {
        // Go visibly stale rather than keep showing a day that has moved on.
        // The next trigger is the first moment this card could be wrong.
        let nextChange = state.current?.triggerDate
            ?? state.upcoming.compactMap(\.triggerDate).first
        let stale = nextChange.map { max($0, now.addingTimeInterval(60)) }
            ?? now.addingTimeInterval(3600)
        return ActivityContent(state: state, staleDate: stale)
    }

    private func start(
        day: Date,
        state: DaybookActivityAttributes.ContentState,
        now: Date
    ) {
        do {
            _ = try Activity.request(
                attributes: DaybookActivityAttributes(day: day),
                content: content(state, now: now),
                // Phase 4 swaps this for `.token` and keeps everything else.
                pushType: nil
            )
            startedAt = now
        } catch {
            // Refused when the user has switched Live Activities off, or when
            // too many are already running. Neither is worth interrupting them
            // about: every other surface still works.
            startedAt = nil
        }
    }

    // MARK: - Crossing into ActivityKit
    //
    // `Activity` cannot be carried from the main actor into ActivityKit's
    // nonisolated async methods. These two fetch it and use it inside the same
    // nonisolated context, so nothing is ever sent across a boundary.

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
