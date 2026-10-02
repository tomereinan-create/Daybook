import AppIntents
import SwiftUI
import WidgetKit

/// The large widget: the whole point of the app. Meant to hold the top of the
/// first home page, with the medium one below it.
///
/// Drawn to the Daybook design: a coloured ground holding the day and the
/// count, and a paper card with the next thing big, the rest of the list
/// below it, and quota habits as tiles at the foot.
nonisolated struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.today, intent: TodayWidgetConfiguration.self, provider: TodayTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(DaybookPalette.ground, for: .widget)
        }
        .configurationDisplayName("widget.today.name")
        .description("widget.today.description")
        .supportedFamilies([.systemLarge, .systemMedium])
        // The card sits 8pt in from the edge, as in the design, rather than
        // inside the system's wider margins.
        .contentMarginsDisabled()
    }
}

nonisolated enum WidgetKind {
    static let today = "DaybookToday"
    static let nextUp = "DaybookNextUp"
    static let progress = "DaybookProgress"
}

/// The design's colours. Fixed rather than following light and dark: the
/// widget is a coloured object on the home screen, not a system surface.
nonisolated enum DaybookPalette {
    static let ground = Color(red: 0x2B / 255, green: 0x41 / 255, blue: 0x70 / 255)
    static let paper = Color(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF6 / 255)
    static let ink = Color(red: 0x1E / 255, green: 0x24 / 255, blue: 0x30 / 255)
    static let muted = Color(red: 0x5B / 255, green: 0x61 / 255, blue: 0x70 / 255)
    /// Late. Darker than the ground's orange would be, so it passes contrast
    /// on paper and differs from the accent in lightness, not only hue.
    static let late = Color(red: 0xA0 / 255, green: 0x46 / 255, blue: 0x06 / 255)
    static let rule = Color(red: 0xE7 / 255, green: 0xE4 / 255, blue: 0xDC / 255)
    static let snoozeFill = Color(red: 0xEE / 255, green: 0xEB / 255, blue: 0xE3 / 255)
    static let tile = Color(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
    static let circle = Color(red: 0x7C / 255, green: 0x81 / 255, blue: 0x8C / 255)
    static let dotEmpty = Color(red: 0xB3 / 255, green: 0xB6 / 255, blue: 0xBE / 255)
}

extension Font {
    /// The design's display face: New York.
    static func daybookSerif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var isLarge: Bool { family == .systemLarge }

    /// Quota habits get tiles of their own; everything else is the list.
    private var tasks: [WidgetRow] { entry.rows.filter { $0.quota == nil } }
    private var habits: [WidgetRow] { entry.rows.filter { $0.quota != nil } }

    var body: some View {
        VStack(spacing: 0) {
            DaybookHeader(entry: entry, compact: !isLarge)
                .padding(.horizontal, 16)
                .padding(.top, isLarge ? 12 : 10)
                .padding(.bottom, isLarge ? 8 : 6)

            card
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.isUnavailable {
                UnavailableView()
            } else {
                if let hero = tasks.first {
                    HeroView(row: hero, date: entry.date, compact: !isLarge)
                        // Changes while nobody is looking. A crossfade keyed on
                        // the item is the quietest honest transition.
                        .id(hero.id)
                        .transition(.opacity)
                } else {
                    ClearView(doneCount: entry.doneCount, height: isLarge ? 96 : 84)
                }
                if isLarge {
                    list
                    Spacer(minLength: 8)
                    habitTiles
                }
            }
            Spacer(minLength: 0)
        }
        .padding(isLarge ? 12 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DaybookPalette.paper, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// A large widget holds three rows beside the habit tiles, five without.
    private var rowLimit: Int { habits.isEmpty ? 5 : 3 }

    @ViewBuilder
    private var list: some View {
        let rest = Array(tasks.dropFirst())
        if !rest.isEmpty {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(DaybookPalette.rule)
                    .frame(height: 1)
                if rest.count > rowLimit {
                    Text("widget.more \(rest.count - rowLimit)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DaybookPalette.muted)
                        .fixedSize()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 2)

            ForEach(rest.prefix(rowLimit)) { row in
                DaybookRowView(row: row, date: entry.date)
            }
        }
    }

    @ViewBuilder
    private var habitTiles: some View {
        if !habits.isEmpty {
            HStack(spacing: 8) {
                ForEach(habits.prefix(2)) { row in
                    HabitTile(row: row)
                }
            }
        }
    }
}

/// The day, the count, and a way into the app to add something.
struct DaybookHeader: View {
    let entry: TodayEntry
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.date, format: .dateTime.weekday(.wide))
                    .font(.daybookSerif(compact ? 20 : 28))
                if !compact {
                    Text(entry.date, format: .dateTime.day().month(.wide))
                        .font(.system(size: 12))
                        .opacity(0.78)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: compact ? "\(entry.doneCount)/\(entry.totalCount)" : "\(entry.doneCount)")
                    .font(compact ? Font.system(size: 15, weight: .semibold) : Font.daybookSerif(28))
                    .monospacedDigit()
                    // The only number on the widget that changes on its own,
                    // so it is the only thing worth transitioning.
                    .contentTransition(.numericText(value: Double(entry.doneCount)))
                if !compact {
                    Text("widget.ofDone \(entry.totalCount)")
                        .font(.system(size: 11))
                        .opacity(0.78)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("widget.progress.value \(entry.doneCount) \(entry.totalCount)"))

            Link(destination: URL(string: "daybook://new")!) {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                    .background(DaybookPalette.paper.opacity(0.16), in: .circle)
            }
            .accessibilityLabel(Text("action.newItem"))
        }
        .foregroundStyle(DaybookPalette.paper)
    }
}

/// The next thing, big, with Done and Snooze.
struct HeroView: View {
    let row: WidgetRow
    let date: Date
    /// The medium widget has less height to give.
    var compact: Bool = false

    private var buttonHeight: CGFloat { compact ? 36 : 40 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            meta
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: 18, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.title)
                    .font(.daybookSerif(compact ? 20 : 23))
                    .foregroundStyle(DaybookPalette.ink)
                    .lineLimit(1)
                if row.isMandatory {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(DaybookPalette.late)
                        .accessibilityLabel(Text("a11y.mandatory"))
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(intent: CompleteOccurrenceIntent(row.reference)) {
                    Label("action.done", systemImage: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DaybookPalette.paper)
                        .frame(maxWidth: .infinity, minHeight: buttonHeight)
                        .background(DaybookPalette.ground, in: .rect(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                // The tap has to reload a timeline before anything visibly
                // changes. This is what tells the user it was heard meanwhile.
                .invalidatableContent()

                if let minutes = row.snoozeMinutes {
                    Button(intent: SnoozeOccurrenceIntent(row.reference)) {
                        Label {
                            Text("alarm.snoozeMinutes \(minutes)")
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DaybookPalette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: buttonHeight)
                        .background(DaybookPalette.snoozeFill, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .invalidatableContent()
                }
            }
        }
        .frame(height: compact ? 84 : 96)
    }

    @ViewBuilder
    private var meta: some View {
        if let countdown = row.countdown, countdown.upperBound > date {
            Text("widget.readyIn \(Text(timerInterval: countdown, countsDown: true))")
                .foregroundStyle(DaybookPalette.ground)
        } else if let trigger = row.trigger {
            let time = trigger.formatted(date: .omitted, time: .shortened)
            if row.state == .overdue {
                Text("widget.overdue \(time)")
                    .foregroundStyle(DaybookPalette.late)
            } else {
                Text("widget.due \(time)")
                    .foregroundStyle(DaybookPalette.ground)
            }
        } else if let detail = row.detail {
            Text(detail)
                .foregroundStyle(DaybookPalette.ground)
        }
    }
}

/// One line of the list. The circle is a real button running an AppIntent, so
/// it works with the app closed.
struct DaybookRowView: View {
    let row: WidgetRow
    let date: Date

    private var isLate: Bool { row.state == .overdue }

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteOccurrenceIntent(row.reference)) {
                Circle()
                    .strokeBorder(isLate ? DaybookPalette.late : DaybookPalette.circle, lineWidth: 1.6)
                    .frame(width: 20, height: 20)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityLabel(Text("a11y.markDone"))

            Text(row.title)
                .font(.system(size: 14))
                .foregroundStyle(DaybookPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 6)

            trailing

            if row.isMandatory {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(DaybookPalette.late)
                    .accessibilityLabel(Text("a11y.mandatory"))
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var trailing: some View {
        if let countdown = row.countdown, countdown.upperBound > date {
            HStack(spacing: 5) {
                ProgressView(
                    timerInterval: countdown,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.circular)
                .tint(DaybookPalette.ground)
                .frame(width: 14, height: 14)

                Text(timerInterval: countdown, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 44, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DaybookPalette.ground)
        } else if let trailing = row.trailing {
            Text(trailing)
                .font(.system(size: 12, weight: isLate ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isLate ? DaybookPalette.late : DaybookPalette.muted)
                .lineLimit(1)
        }
    }
}

/// A quota habit. Tapping the tile tallies one, the same as its circle would.
struct HabitTile: View {
    let row: WidgetRow

    var body: some View {
        if let quota = row.quota {
            Button(intent: CompleteOccurrenceIntent(row.reference)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // Past a week's worth the dots stop meaning anything at
                        // a glance; the line below still says the number.
                        if quota.target <= 7 {
                            HStack(spacing: 3) {
                                ForEach(0..<quota.target, id: \.self) { index in
                                    dot(filled: index < quota.done)
                                }
                            }
                        }
                    }
                    Group {
                        if row.isBehindPace {
                            Text("widget.quotaBehind \(quota.done) \(quota.target)")
                                .foregroundStyle(DaybookPalette.late)
                        } else {
                            Text("widget.quota \(quota.done) \(quota.target)")
                                .foregroundStyle(DaybookPalette.muted)
                        }
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                }
                .foregroundStyle(DaybookPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background(DaybookPalette.tile, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("a11y.markDone"))
        }
    }

    @ViewBuilder
    private func dot(filled: Bool) -> some View {
        if filled {
            Circle()
                .fill(DaybookPalette.ground)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .strokeBorder(DaybookPalette.dotEmpty, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }
}

/// Nothing left today. Worth saying properly rather than showing an empty box.
struct ClearView: View {
    let doneCount: Int
    var height: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if doneCount > 0 {
                Text("widget.clear.count \(doneCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaybookPalette.ground)
            }
            Text("widget.clear.title")
                .font(.daybookSerif(23))
                .foregroundStyle(DaybookPalette.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }
}

/// The App Group container was unavailable, so this process cannot see the
/// user's day. Say so; do not draw a plausible empty one.
struct UnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(DaybookPalette.late)
            Text("widget.unavailable.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DaybookPalette.ink)
            Text("widget.unavailable.body")
                .font(.caption)
                .foregroundStyle(DaybookPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

nonisolated extension OccurrenceState {
    /// Differs in lightness as well as hue, so the states stay distinguishable
    /// in greyscale and to a colour-blind reader.
    var widgetTint: Color {
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

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry.placeholder
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry.placeholder
}
