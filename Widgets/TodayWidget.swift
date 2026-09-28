import AppIntents
import SwiftUI
import WidgetKit

/// The large widget: the whole point of the app. Meant to hold the top of the
/// first home page, with the medium one below it.
nonisolated struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("widget.today.name")
        .description("widget.today.description")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

nonisolated enum WidgetKind {
    static let today = "DaybookToday"
    static let nextUp = "DaybookNextUp"
    static let progress = "DaybookProgress"
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var rowLimit: Int {
        family == .systemLarge ? 8 : 3
    }

    var body: some View {
        if entry.isUnavailable {
            UnavailableView()
        } else if entry.rows.isEmpty {
            ClearView(doneCount: entry.doneCount)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 2 : 1) {
                header
                ForEach(entry.rows.prefix(rowLimit)) { row in
                    WidgetRowView(row: row, compact: family != .systemLarge)
                }
                if entry.rows.count > rowLimit {
                    Text("widget.more \(entry.rows.count - rowLimit)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("today.title")
                .font(.system(.title3, design: .serif))
            Spacer()
            Text(verbatim: "\(entry.doneCount)/\(entry.totalCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                // The only number on the widget that changes on its own, so
                // it is the only thing worth transitioning.
                .contentTransition(.numericText())
        }
        .padding(.bottom, 6)
    }
}

/// One line. The circle is a real button running an AppIntent, so it works with
/// the app closed.
struct WidgetRowView: View {
    let row: WidgetRow
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: CompleteOccurrenceIntent(row.reference)) {
                CompletionCircle(state: row.state, quota: row.quota)
            }
            .buttonStyle(.plain)
            // The tap has to reload a timeline before anything visibly changes.
            // This is what tells the user it was heard in the meantime.
            .invalidatableContent()
            .accessibilityLabel(Text("a11y.markDone"))

            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .lineLimit(1)
                if let detail = row.detail, !compact {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let quota = row.quota {
                Text(verbatim: "\(quota.done)/\(quota.target)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(row.state.widgetTint)
            } else if let trailing = row.trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if row.isMandatory {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("a11y.mandatory"))
            }
        }
        .frame(minHeight: compact ? 28 : 32)
    }
}

struct CompletionCircle: View {
    let state: OccurrenceState
    var quota: (done: Int, target: Int)?

    private var symbol: String {
        if state == .done { return "checkmark.circle.fill" }
        if let quota, quota.done > 0 { return "circle.dotted" }
        return "circle"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(state == .done ? Color.green : state.widgetTint)
            // Circle to checkmark is a symbol swap, not a movement. Replace is
            // the right effect and the system owns its timing.
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, height: 22)
    }
}

/// Nothing left today. Worth saying properly rather than showing an empty box.
struct ClearView: View {
    let doneCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("today.title")
                .font(.system(.title3, design: .serif))
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(.green)
            Text("widget.clear.title")
                .font(.subheadline.weight(.semibold))
            if doneCount > 0 {
                Text("widget.clear.count \(doneCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The App Group container was unavailable, so this process cannot see the
/// user's day. Say so; do not draw a plausible empty one.
struct UnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("widget.unavailable.title")
                .font(.subheadline.weight(.semibold))
            Text("widget.unavailable.body")
                .font(.caption)
                .foregroundStyle(.secondary)
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
