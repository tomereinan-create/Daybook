import SwiftUI

/// One editable setting group. The editor composes these; none of them knows
/// which preset it was reached from.
struct SettingFieldView: View {
    let field: SettingField
    @Binding var settings: ItemSettings

    var body: some View {
        switch field {
        case .trigger: TriggerField(settings: $settings)
        case .recurrence: RecurrenceField(settings: $settings)
        case .quota: QuotaField(settings: $settings)
        case .location: LocationField(settings: $settings)
        case .relativeDuration: RelativeDurationField(settings: $settings)
        case .timerStart: TimerStartField(settings: $settings)
        case .leadTime: LeadTimeField(settings: $settings)
        case .surfaces: SurfacesField(settings: $settings)
        case .intensity: IntensityField(settings: $settings)
        case .preAlerts: PreAlertsField(settings: $settings)
        case .nag: NagField(settings: $settings)
        case .escalation: EscalationField(settings: $settings)
        case .snooze: SnoozeField(settings: $settings)
        case .window: WindowField(settings: $settings)
        case .onMissed: OnMissedField(settings: $settings)
        case .priority: PriorityField(settings: $settings)
        case .quietHours: QuietHoursField(settings: $settings)
        case .steps: StepsField(settings: $settings)
        case .followUpInterval: FollowUpField(settings: $settings)
        }
    }
}

// MARK: - Trigger

/// Trigger kinds the app can honour. `afterPrevious` is not offered: routines
/// already chain through `steps`, and chaining separate items is a different
/// feature nobody has asked for yet.
private let availableTriggerKinds: [TriggerKind] = [.time, .relative, .location, .none]

private struct TriggerField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.trigger", selection: kindBinding) {
            ForEach(availableTriggerKinds, id: \.self) { kind in
                Text(kind.label).tag(kind)
            }
        }

        if settings.trigger.kind == .time {
            if settings.recurrence.frequency.repeats {
                DatePicker(
                    "field.timeOfDay",
                    selection: timeOfDayBinding,
                    displayedComponents: .hourAndMinute
                )
            } else {
                DatePicker(
                    "field.dateAndTime",
                    selection: dateBinding,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    private var kindBinding: Binding<TriggerKind> {
        Binding(
            get: { settings.trigger.kind },
            set: { newValue in
                settings.trigger.kind = newValue
                if newValue == .time, settings.trigger.date == nil, settings.trigger.timeOfDay == nil {
                    settings.trigger.timeOfDay = TimeOfDay(hour: 9, minute: 0)
                    settings.trigger.date = Calendar.current.nextHour(after: .now)
                }
                if newValue == .relative, settings.trigger.relativeMinutes == nil {
                    settings.trigger.relativeMinutes = 30
                }
                // And the other way round: taking the time away leaves a
                // repeat with nothing to hang off, so it stops repeating.
                if newValue != .time, settings.recurrence.frequency.repeats,
                   !settings.recurrence.frequency.isQuota {
                    settings.recurrence.frequency = .once
                }
            }
        )
    }

    private var timeOfDayBinding: Binding<Date> {
        Binding(
            get: {
                let time = settings.trigger.timeOfDay ?? TimeOfDay(hour: 9, minute: 0)
                return Calendar.current.date(setting: time, on: .now) ?? .now
            },
            set: { settings.trigger.timeOfDay = Calendar.current.timeOfDay(of: $0) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { settings.trigger.date ?? Calendar.current.nextHour(after: .now) },
            set: { settings.trigger.date = $0 }
        )
    }
}

// MARK: - Recurrence

private enum FrequencyKind: String, CaseIterable, Identifiable {
    case once, daily, weekdays, everyNDays, dayOfMonth, quota
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .once: "frequency.once"
        case .daily: "frequency.daily"
        case .weekdays: "frequency.weekdays"
        case .everyNDays: "frequency.everyNDays"
        case .dayOfMonth: "frequency.dayOfMonth"
        case .quota: "frequency.quota"
        }
    }
}

private extension Frequency {
    var kind: FrequencyKind {
        switch self {
        case .once: .once
        case .daily: .daily
        case .weekdays: .weekdays
        case .everyNDays: .everyNDays
        case .dayOfMonth: .dayOfMonth
        case .quota: .quota
        }
    }

    static func make(_ kind: FrequencyKind, from existing: Frequency) -> Frequency {
        switch kind {
        case .once: .once
        case .daily: .daily
        case .weekdays:
            if case .weekdays(let days) = existing { .weekdays(days) }
            else { .weekdays([.monday, .tuesday, .wednesday, .thursday, .friday]) }
        case .everyNDays:
            if case .everyNDays(let n) = existing { .everyNDays(n) } else { .everyNDays(2) }
        case .dayOfMonth:
            if case .dayOfMonth(let d) = existing { .dayOfMonth(d) } else { .dayOfMonth(1) }
        case .quota:
            if case .quota(let c, let p) = existing { .quota(count: c, period: p) }
            else { .quota(count: 3, period: .week) }
        }
    }
}

private struct RecurrenceField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.repeats", selection: kindBinding) {
            ForEach(FrequencyKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }

        if case .weekdays(let days) = settings.recurrence.frequency {
            WeekdayPicker(selected: days) { settings.recurrence.frequency = .weekdays($0) }
        }
        if case .everyNDays(let n) = settings.recurrence.frequency {
            Stepper(value: intervalBinding(current: n), in: 1...60) {
                Text("field.everyNDays \(n)")
            }
        }
        if case .dayOfMonth(let day) = settings.recurrence.frequency {
            Stepper(value: dayOfMonthBinding(current: day), in: 1...31) {
                Text("field.dayOfMonth \(day)")
            }
        }
        if settings.recurrence.frequency.repeats {
            RecurrenceEndField(settings: $settings)
        }
    }

    private var kindBinding: Binding<FrequencyKind> {
        Binding(
            get: { settings.recurrence.frequency.kind },
            set: { newKind in
                settings.recurrence.frequency = .make(newKind, from: settings.recurrence.frequency)
                // Nothing can repeat without a time to repeat at. A quota is
                // the exception: it has no time on purpose.
                if newKind != .once, newKind != .quota, settings.trigger.kind != .time {
                    settings.trigger.kind = .time
                    if settings.trigger.timeOfDay == nil {
                        settings.trigger.timeOfDay = TimeOfDay(hour: 9, minute: 0)
                    }
                }
            }
        )
    }

    private func intervalBinding(current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { settings.recurrence.frequency = .everyNDays(max($0, 1)) }
        )
    }

    private func dayOfMonthBinding(current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { settings.recurrence.frequency = .dayOfMonth(min(max($0, 1), 31)) }
        )
    }
}

private struct WeekdayPicker: View {
    let selected: Set<Weekday>
    let onChange: (Set<Weekday>) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let isOn = selected.contains(day)
                Button {
                    var next = selected
                    if isOn { next.remove(day) } else { next.insert(day) }
                    if !next.isEmpty { onChange(next) }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isOn ? Color.accentColor : Color.clear, in: .capsule)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.accessibilityLabel)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private enum RecurrenceEndKind: String, CaseIterable, Identifiable {
    case never, until, afterCount
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .never: "end.never"
        case .until: "end.until"
        case .afterCount: "end.afterCount"
        }
    }
}

private struct RecurrenceEndField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.ends", selection: kindBinding) {
            ForEach(RecurrenceEndKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        if case .until(let date) = settings.recurrence.end {
            DatePicker(
                "field.endDate",
                selection: Binding(
                    get: { date },
                    set: { settings.recurrence.end = .until($0) }
                ),
                displayedComponents: .date
            )
        }
        if case .afterOccurrences(let count) = settings.recurrence.end {
            Stepper(
                value: Binding(
                    get: { count },
                    set: { settings.recurrence.end = .afterOccurrences(max($0, 1)) }
                ),
                in: 1...365
            ) {
                Text("field.afterCount \(count)")
            }
        }
    }

    private var kindBinding: Binding<RecurrenceEndKind> {
        Binding(
            get: {
                switch settings.recurrence.end {
                case .never: .never
                case .until: .until
                case .afterOccurrences: .afterCount
                }
            },
            set: { kind in
                switch kind {
                case .never:
                    settings.recurrence.end = .never
                case .until:
                    let inAMonth = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
                    settings.recurrence.end = .until(inAMonth)
                case .afterCount:
                    settings.recurrence.end = .afterOccurrences(10)
                }
            }
        )
    }
}

// MARK: - Quota

private struct QuotaField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Stepper(value: countBinding, in: 1...30) {
            Text("field.quotaCount \(count)")
        }
        Picker("field.quotaPeriod", selection: periodBinding) {
            Text("period.week").tag(QuotaPeriod.week)
            Text("period.month").tag(QuotaPeriod.month)
        }
    }

    private var current: (count: Int, period: QuotaPeriod) {
        if case .quota(let count, let period) = settings.recurrence.frequency {
            return (count, period)
        }
        return (3, .week)
    }

    private var count: Int { current.count }

    private var countBinding: Binding<Int> {
        Binding(
            get: { current.count },
            set: { settings.recurrence.frequency = .quota(count: max($0, 1), period: current.period) }
        )
    }

    private var periodBinding: Binding<QuotaPeriod> {
        Binding(
            get: { current.period },
            set: { settings.recurrence.frequency = .quota(count: current.count, period: $0) }
        )
    }
}

// MARK: - Simple fields

private struct RelativeDurationField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Stepper(value: binding, in: 1...600, step: 5) {
            Text("field.relativeMinutes \(settings.trigger.relativeMinutes ?? 30)")
        }
    }

    private var binding: Binding<Int> {
        Binding(
            get: { settings.trigger.relativeMinutes ?? 30 },
            set: { settings.trigger.relativeMinutes = max($0, 1) }
        )
    }
}

/// A countdown either runs on its own or waits to be started. Shown only for
/// countdowns; for anything else there is nothing here to decide.
private struct TimerStartField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        if settings.trigger.kind == .relative {
            Toggle("field.startsImmediately", isOn: binding)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { settings.trigger.runsUnattended },
            set: { settings.trigger.startsImmediately = $0 }
        )
    }
}

private let leadTimeChoices: [TimeInterval] = [0, 900, 1800, 3600, 2 * 3600, 4 * 3600, 24 * 3600]

private struct LeadTimeField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.leadTime", selection: $settings.visibility.leadTime) {
            ForEach(leadTimeChoices, id: \.self) { value in
                Text(value == 0 ? String(localized: "leadTime.atTheTime") : Formatting.duration(value))
                    .tag(value)
            }
        }
    }
}

private struct SurfacesField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.surface.lockScreen", isOn: surfaceBinding(.liveActivity))
        Toggle("field.surface.homeWidget", isOn: surfaceBinding(.homeWidget))
    }

    private func surfaceBinding(_ member: SurfaceSet) -> Binding<Bool> {
        Binding(
            get: { settings.visibility.surfaces.contains(member) },
            set: { isOn in
                if isOn { settings.visibility.surfaces.insert(member) }
                else { settings.visibility.surfaces.remove(member) }
            }
        )
    }
}

private struct IntensityField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.intensity", selection: $settings.alerting.intensity) {
            ForEach(Intensity.allCases, id: \.self) { value in
                Text(value.label).tag(value)
            }
        }
    }
}

private let preAlertChoices: [TimeInterval] = [300, 600, 900, 1800, 3600, 2 * 3600, 24 * 3600]

private struct PreAlertsField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        ForEach(settings.alerting.preAlertOffsets.sorted(by: >), id: \.self) { offset in
            HStack {
                Text("preAlert.before \(Formatting.duration(offset))")
                Spacer()
                Button("action.remove", systemImage: "minus.circle") {
                    settings.alerting.preAlertOffsets.removeAll { $0 == offset }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        Menu("action.addPreAlert") {
            ForEach(preAlertChoices, id: \.self) { offset in
                Button(Formatting.duration(offset)) {
                    guard !settings.alerting.preAlertOffsets.contains(offset) else { return }
                    settings.alerting.preAlertOffsets.append(offset)
                }
            }
        }
    }
}

private struct NagField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.nag", isOn: $settings.alerting.nag.isEnabled)
        if settings.alerting.nag.isEnabled {
            Stepper(value: $settings.alerting.nag.intervalMinutes, in: 1...240, step: 5) {
                Text("field.nagInterval \(settings.alerting.nag.intervalMinutes)")
            }
            Stepper(value: $settings.alerting.nag.maxRepeats, in: 1...20) {
                Text("field.nagRepeats \(settings.alerting.nag.maxRepeats)")
            }
        }
    }
}

private struct EscalationField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.escalation", isOn: $settings.alerting.escalates)
    }
}

private struct SnoozeField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.snooze", isOn: $settings.alerting.snoozeAllowed)
        if settings.alerting.snoozeAllowed {
            Stepper(value: $settings.alerting.snoozeMinutes, in: 1...120, step: 1) {
                Text("field.snoozeMinutes \(settings.alerting.snoozeMinutes)")
            }
        }
    }
}

private enum EndConditionKind: String, CaseIterable, Identifiable {
    case markedDone, eventStart, windowEnds, atTime, manualOnly
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .markedDone: "endCondition.markedDone"
        case .eventStart: "endCondition.eventStart"
        case .windowEnds: "endCondition.windowEnds"
        case .atTime: "endCondition.atTime"
        case .manualOnly: "endCondition.manualOnly"
        }
    }
}

private let windowChoices: [TimeInterval] = [900, 1800, 3600, 2 * 3600, 3 * 3600, 6 * 3600, 12 * 3600]

private struct WindowField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.disappearsWhen", selection: kindBinding) {
            ForEach(EndConditionKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        if case .windowEnds(let duration) = settings.dismissal.endCondition {
            Picker("field.windowLength", selection: durationBinding(current: duration)) {
                ForEach(windowChoices, id: \.self) { value in
                    Text(Formatting.duration(value)).tag(value)
                }
            }
        }
        if case .atTime(let time) = settings.dismissal.endCondition {
            DatePicker(
                "field.disappearsAt",
                selection: timeBinding(current: time),
                displayedComponents: .hourAndMinute
            )
        }
    }

    private var kindBinding: Binding<EndConditionKind> {
        Binding(
            get: {
                switch settings.dismissal.endCondition {
                case .markedDone: .markedDone
                case .eventStart: .eventStart
                case .windowEnds: .windowEnds
                case .atTime: .atTime
                case .manualOnly: .manualOnly
                }
            },
            set: { kind in
                switch kind {
                case .markedDone: settings.dismissal.endCondition = .markedDone
                case .eventStart: settings.dismissal.endCondition = .eventStart
                case .windowEnds: settings.dismissal.endCondition = .windowEnds(3600)
                case .atTime: settings.dismissal.endCondition = .atTime(TimeOfDay(hour: 22, minute: 0))
                case .manualOnly: settings.dismissal.endCondition = .manualOnly
                }
            }
        )
    }

    private func durationBinding(current: TimeInterval) -> Binding<TimeInterval> {
        Binding(
            get: { current },
            set: { settings.dismissal.endCondition = .windowEnds($0) }
        )
    }

    private func timeBinding(current: TimeOfDay) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(setting: current, on: .now) ?? .now },
            set: { settings.dismissal.endCondition = .atTime(Calendar.current.timeOfDay(of: $0)) }
        )
    }
}

private struct OnMissedField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Picker("field.onMissed", selection: $settings.dismissal.onMissed) {
            ForEach(MissedPolicy.allCases, id: \.self) { policy in
                Text(policy.label).tag(policy)
            }
        }
    }
}

private struct PriorityField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.mandatory", isOn: binding)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { settings.priority == .mandatory },
            set: { settings.priority = $0 ? .mandatory : .normal }
        )
    }
}

private struct QuietHoursField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.ignoreQuietHours", isOn: binding)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { settings.quietHours == .override },
            set: { settings.quietHours = $0 ? .override : .respect }
        )
    }
}

private struct StepsField: View {
    @Binding var settings: ItemSettings
    @State private var newStep = ""

    var body: some View {
        ForEach(settings.steps) { step in
            Text(step.title)
        }
        .onDelete { offsets in
            settings.steps.remove(atOffsets: offsets)
        }
        .onMove { source, destination in
            settings.steps.move(fromOffsets: source, toOffset: destination)
        }
        HStack {
            TextField("field.newStep", text: $newStep)
                .onSubmit(addStep)
            Button("action.addStep", systemImage: "plus.circle") { addStep() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        settings.steps.append(Step(title: title))
        newStep = ""
    }
}

private struct FollowUpField: View {
    @Binding var settings: ItemSettings

    var body: some View {
        Toggle("field.followUp", isOn: $settings.alerting.nag.isEnabled)
        if settings.alerting.nag.isEnabled {
            Stepper(value: dayBinding, in: 1...60) {
                Text("field.followUpDays \(days)")
            }
        }
    }

    private var days: Int { max(settings.alerting.nag.intervalMinutes / (24 * 60), 1) }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { days },
            set: { settings.alerting.nag.intervalMinutes = max($0, 1) * 24 * 60 }
        )
    }
}
