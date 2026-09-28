import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The lock screen card and the Dynamic Island.
nonisolated struct DaybookLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DaybookActivityAttributes.self) { context in
            LockScreenCard(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.current(at: context.state)?.state.islandSymbol ?? "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(context.attributes.current(at: context.state)?.state.widgetTint ?? .green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let trigger = context.attributes.current(at: context.state)?.triggerDate {
                        Text(trigger, style: .relative)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.current(at: context.state)?.title ?? String(localized: "widget.clear.title"))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let item = context.attributes.current(at: context.state) {
                        ActionRow(item: item)
                    }
                }
            } compactLeading: {
                Image(systemName: "circle")
                    .foregroundStyle(context.attributes.current(at: context.state)?.state.widgetTint ?? .secondary)
            } compactTrailing: {
                if let trigger = context.attributes.current(at: context.state)?.triggerDate {
                    Text(trigger, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text(verbatim: "\(context.state.doneCount)/\(context.state.totalCount)")
                        .font(.caption2.weight(.bold))
                }
            } minimal: {
                Image(systemName: "circle")
                    .foregroundStyle(context.attributes.current(at: context.state)?.state.widgetTint ?? .secondary)
            }
            // The island's own expansion spring belongs to the system. Tapping
            // it opens the app on the item rather than doing anything clever.
            .widgetURL(context.attributes.current(at: context.state).map { URL(string: "daybook://item/\($0.itemID)")! })
        }
    }
}

struct LockScreenCard: View {
    let attributes: DaybookActivityAttributes
    let state: DaybookActivityAttributes.ContentState

    private var upcoming: [LiveItem] { attributes.upcoming(at: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let current = attributes.current(at: state) {
                CurrentItemView(item: current)
                if !upcoming.isEmpty {
                    Divider().opacity(0.25)
                    ForEach(upcoming) { item in
                        UpcomingRow(item: item)
                    }
                }
            } else {
                Text("widget.clear.title")
                    .font(.headline)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Text(verbatim: "Daybook")
                .font(.system(.footnote, design: .serif))
            Spacer()
            Text(verbatim: "\(state.doneCount)/\(state.totalCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }
}

struct CurrentItemView: View {
    let item: LiveItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let subtitle = item.subtitle {
                Text(subtitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if item.isMandatory {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("a11y.mandatory"))
                }
            }
            ActionRow(item: item)
        }
        // The card changes under the user while they are not looking. A
        // crossfade keyed on the item is the quietest way to not lie.
        .id(item.id)
        .transition(.opacity)
    }
}

/// Done and Snooze. `LiveActivityIntent` is what lets these run from the lock
/// screen without unlocking.
struct ActionRow: View {
    let item: LiveItem

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteOccurrenceIntent(item.reference)) {
                Label("action.done", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)

            if let minutes = item.snoozeMinutes {
                Button(intent: SnoozeOccurrenceIntent(item.reference)) {
                    Text("alarm.snoozeMinutes \(minutes)")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 34)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct UpcomingRow: View {
    let item: LiveItem

    var body: some View {
        HStack(spacing: 8) {
            if let trigger = item.triggerDate {
                Text(trigger, style: .time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
            } else {
                Text(verbatim: "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 46, alignment: .leading)
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

nonisolated extension OccurrenceState {
    var islandSymbol: String {
        switch self {
        case .overdue, .missed: "exclamationmark.circle"
        case .active: "timer"
        case .done: "checkmark.circle.fill"
        default: "circle"
        }
    }
}
