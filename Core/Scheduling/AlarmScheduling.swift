import AlarmKit
import Foundation
import SwiftUI

nonisolated enum AlarmAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    case authorized

    var canSchedule: Bool { self == .authorized }
}

/// What the app needs from AlarmKit, behind a protocol so the coordinator can
/// be tested without the framework.
nonisolated protocol AlarmScheduling: Sendable {
    func scheduledIdentifiers() async -> Set<UUID>
    func schedule(_ alarm: PlannedAlarm) async throws
    func cancel(ids: [UUID]) async
    func authorizationStatus() async -> AlarmAuthorization
    func requestAuthorization() async -> AlarmAuthorization
}

/// Metadata travels with the alarm so the app can find the occurrence again
/// when the alarm is stopped.
nonisolated struct DaybookAlarmMetadata: AlarmMetadata {
    var itemID: UUID
    var slot: Date

    var key: OccurrenceKey { OccurrenceKey(itemID: itemID, slot: slot) }

    init(key: OccurrenceKey) {
        self.itemID = key.itemID
        self.slot = key.slot
    }
}

nonisolated struct SystemAlarmScheduler: AlarmScheduling {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var manager: AlarmManager { .shared }

    func scheduledIdentifiers() async -> Set<UUID> {
        // `alarms` can throw when the store is unavailable. An empty set is the
        // safe answer: the coordinator then re-schedules what it wants rather
        // than cancelling things it could not see.
        let existing = (try? manager.alarms) ?? []
        return Set(existing.map(\.id))
    }

    func schedule(_ alarm: PlannedAlarm) async throws {
        let metadata = DaybookAlarmMetadata(key: alarm.key)

        // Snooze is not a button behaviour of its own. It is a countdown that
        // starts once the alarm has alerted, which is what the `postAlert`
        // duration below sets up; the button just has to start it.
        let secondary: AlarmButton? = alarm.snoozeMinutes.map { minutes in
            AlarmButton(
                text: LocalizedStringResource("alarm.snoozeMinutes \(minutes)"),
                textColor: .white,
                systemImageName: "moon.zzz.fill"
            )
        }

        let title = LocalizedStringResource(stringLiteral: alarm.title)
        let behaviour: AlarmPresentation.Alert.SecondaryButtonBehavior? = secondary == nil ? nil : .countdown

        // The system supplies its own stop affordance from 26.1 onwards. On
        // 26.0 the only initialiser available still wants one, so we describe
        // it. Deployment target stays at 26.0 rather than narrowing who can
        // install the app.
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondary,
                secondaryButtonBehavior: behaviour
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: LocalizedStringResource("alarm.stop"),
                    textColor: .white,
                    systemImageName: "stop.circle"
                ),
                secondaryButton: secondary,
                secondaryButtonBehavior: behaviour
            )
        }

        let attributes = AlarmAttributes<DaybookAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: metadata,
            tintColor: Color.accentColor
        )

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: alarm.snoozeMinutes.map {
                Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval($0) * 60)
            },
            schedule: schedule(for: alarm),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await manager.schedule(id: alarm.alarmID, configuration: configuration)
    }

    func cancel(ids: [UUID]) async {
        for id in ids {
            try? manager.cancel(id: id)
        }
    }

    func authorizationStatus() async -> AlarmAuthorization {
        map(manager.authorizationState)
    }

    func requestAuthorization() async -> AlarmAuthorization {
        guard let state = try? await manager.requestAuthorization() else {
            return map(manager.authorizationState)
        }
        return map(state)
    }

    // MARK: - Mapping

    /// A wake-up repeats on weekdays, so it is expressed as a relative schedule
    /// rather than a fixed date: the system then keeps it at 07:00 local
    /// however the clocks or the time zone move.
    private func schedule(for alarm: PlannedAlarm) -> Alarm.Schedule {
        guard !alarm.weekdays.isEmpty else {
            return .fixed(alarm.fireDate)
        }
        let components = calendar.dateComponents([.hour, .minute], from: alarm.fireDate)
        let time = Alarm.Schedule.Relative.Time(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        return .relative(
            Alarm.Schedule.Relative(
                time: time,
                repeats: .weekly(alarm.weekdays.map(\.localeWeekday))
            )
        )
    }

    private func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
