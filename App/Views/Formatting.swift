import Foundation
import SwiftUI

/// User-facing text for engine values. The engine itself stays wordless.
enum Formatting {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayAndTime(_ date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return time(date)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes],
            width: .abbreviated
        )
        return Duration.seconds(max(seconds, 0)).formatted(style)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        duration(date.timeIntervalSince(now))
    }
}

extension OccurrenceState {
    var label: LocalizedStringKey {
        switch self {
        case .upcoming: "state.upcoming"
        case .visible: "state.visible"
        case .active: "state.active"
        case .due: "state.due"
        case .overdue: "state.overdue"
        case .snoozed: "state.snoozed"
        case .done: "state.done"
        case .missed: "state.missed"
        }
    }

    var tint: Color {
        switch self {
        case .overdue, .missed: .red
        case .due: .orange
        case .active: .blue
        case .snoozed: .purple
        case .done: .green
        case .visible, .upcoming: .secondary
        }
    }
}

extension DaySection {
    var title: LocalizedStringKey {
        switch self {
        case .now: "section.now"
        case .upcoming: "section.upcoming"
        case .undated: "section.anytime"
        case .done: "section.done"
        case .missed: "section.missed"
        }
    }
}

extension TriggerKind {
    var label: LocalizedStringKey {
        switch self {
        case .time: "trigger.time"
        case .relative: "trigger.relative"
        case .afterPrevious: "trigger.afterPrevious"
        // Withdrawn, but still a case anything already stored can hold. It
        // reads as having no trigger, which is what it now behaves like.
        case .location, .none: "trigger.none"
        }
    }
}

extension Intensity {
    var label: LocalizedStringKey {
        switch self {
        case .none: "intensity.none"
        case .silent: "intensity.silent"
        case .standard: "intensity.standard"
        case .timeSensitive: "intensity.timeSensitive"
        case .alarm: "intensity.alarm"
        }
    }
}

extension MissedPolicy {
    var label: LocalizedStringKey {
        switch self {
        case .logMissed: "onMissed.log"
        case .rollOver: "onMissed.rollOver"
        case .becomeOpenTask: "onMissed.openTask"
        }
    }
}

extension Weekday {
    /// The calendar's own one- or two-letter symbol, so Hebrew reads as Hebrew.
    var shortLabel: String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = rawValue - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    var accessibilityLabel: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = rawValue - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

extension ResponseKind {
    var label: LocalizedStringKey {
        switch self {
        case .none: "response.none"
        case .number: "response.number"
        case .text: "response.text"
        }
    }
}

extension SettingGroup {
    var title: LocalizedStringKey {
        switch self {
        case .timing: "group.timing"
        case .alerts: "group.alerts"
        case .display: "group.display"
        case .extras: "group.extras"
        }
    }
}

extension PresetKind {
    var title: LocalizedStringKey {
        switch self {
        case .event: "preset.event"
        case .task: "preset.task"
        case .deadlineTask: "preset.deadlineTask"
        case .recurringTask: "preset.recurringTask"
        case .flexibleHabit: "preset.flexibleHabit"
        case .timeBlock: "preset.timeBlock"
        case .relativeTimer: "preset.relativeTimer"
        case .routine: "preset.routine"
        case .waitingFor: "preset.waitingFor"
        case .someday: "preset.someday"
        case .wakeUp: "preset.wakeUp"
        }
    }

    var caption: LocalizedStringKey {
        switch self {
        case .event: "preset.event.caption"
        case .task: "preset.task.caption"
        case .deadlineTask: "preset.deadlineTask.caption"
        case .recurringTask: "preset.recurringTask.caption"
        case .flexibleHabit: "preset.flexibleHabit.caption"
        case .timeBlock: "preset.timeBlock.caption"
        case .relativeTimer: "preset.relativeTimer.caption"
        case .routine: "preset.routine.caption"
        case .waitingFor: "preset.waitingFor.caption"
        case .someday: "preset.someday.caption"
        case .wakeUp: "preset.wakeUp.caption"
        }
    }

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .task: "checkmark.circle"
        case .deadlineTask: "hourglass"
        case .recurringTask: "repeat"
        case .flexibleHabit: "chart.bar"
        case .timeBlock: "rectangle.portrait.and.arrow.right"
        case .relativeTimer: "timer"
        case .routine: "list.number"
        case .waitingFor: "person.crop.circle.badge.clock"
        case .someday: "tray"
        case .wakeUp: "alarm"
        }
    }
}
