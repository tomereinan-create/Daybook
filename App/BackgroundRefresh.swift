import BackgroundTasks
import Foundation

/// Keeps the rolling window rolling while the app is closed.
///
/// iOS holds at most 64 pending notifications, so the app can only ever have
/// the next day or two registered. Something has to top that up without the
/// user opening anything, and a background refresh task is the only sanctioned
/// way to do it. The system decides when, and often decides never — so this is
/// a top-up, never the thing correctness depends on. Everything is also
/// rescheduled on launch and on every change.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let identifier = "com.tomereinan.daybook.refresh"

    /// How far out to ask for the next run. The system treats this as the
    /// earliest acceptable time, not a promise.
    static let interval: TimeInterval = 4 * 3600

    @MainActor
    static func register(handler: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                // Always queue the next one first: if this run is killed, the
                // chain has to survive.
                schedule()
                let work = Task { @MainActor in
                    await handler()
                }
                task.expirationHandler = { work.cancel() }
                await work.value
                task.setTaskCompleted(success: !Task.isCancelled)
            }
        }
    }

    @MainActor
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on the simulator and when the user has switched
            // Background App Refresh off. Neither is an error worth showing:
            // launch and in-app changes still reschedule everything.
        }
    }
}
