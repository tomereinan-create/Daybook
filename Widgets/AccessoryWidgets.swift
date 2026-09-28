import SwiftUI
import WidgetKit

/// Lock screen, rectangular: the one thing happening next.
nonisolated struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextUp, provider: TodayTimelineProvider()) { entry in
            NextUpView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("widget.nextUp.name")
        .description("widget.nextUp.description")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NextUpView: View {
    let entry: TodayEntry

    var body: some View {
        if let row = entry.rows.first {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: row.state == .overdue ? "exclamationmark.circle" : "circle")
                        .font(.caption2)
                    Text(row.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let trailing = row.trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetAccentable()
        } else {
            Label("widget.clear.title", systemImage: "checkmark.circle")
                .font(.headline)
        }
    }
}

/// Lock screen, circular: how much of the day is behind you.
nonisolated struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.progress, provider: TodayTimelineProvider()) { entry in
            ProgressRingView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("widget.progress.name")
        .description("widget.progress.description")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ProgressRingView: View {
    let entry: TodayEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text(verbatim: "\(entry.doneCount)")
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(Text("widget.progress.name"))
        .accessibilityValue(Text("widget.progress.value \(entry.doneCount) \(entry.totalCount)"))
    }
}
