import SwiftData
import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Re-reading these keeps the plan fresh when SwiftData changes underneath.
    @Query private var items: [Item]
    @Query private var records: [OccurrenceRecord]

    @State private var now = Date.now
    @State private var creating = false
    @State private var editing: Item?

    private let sectionOrder: [DaySection] = [.now, .upcoming, .undated, .done, .missed]

    var body: some View {
        // Resolved once per render and handed down. Reading `currentPlan` in
        // each branch would run the engine over the whole lookback window six
        // times for one pass of the screen.
        let plan = currentPlan

        return NavigationStack {
            Group {
                if plan.isEmpty {
                    emptyState
                } else {
                    list(plan)
                }
            }
            .navigationTitle("today.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("action.newItem", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                NewItemFlow()
            }
            .sheet(item: $editing) { item in
                ItemEditorView(item: item)
            }
        }
        .task {
            // One cheap tick keeps countdowns and state transitions honest
            // without a timer that fires while the app is backgrounded.
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var currentPlan: DayPlan {
        // `items` and `records` are read so SwiftUI tracks them; the engine
        // reads the store itself, which is the single source of truth.
        _ = items.count
        _ = records.count
        _ = model.revision
        return model.dayPlan(for: now, now: now)
    }

    private func list(_ plan: DayPlan) -> some View {
        List {
            ForEach(sectionOrder, id: \.self) { section in
                let entries = plan[section]
                if !entries.isEmpty {
                    Section(section.title) {
                        ForEach(entries) { occurrence in
                            OccurrenceRow(occurrence: occurrence, now: now) {
                                editing = model.store.item(with: occurrence.item.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("today.empty.title", systemImage: "checkmark.circle")
        } description: {
            Text("today.empty.description")
        } actions: {
            Button("action.newItem") { creating = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// One line on the Today screen.
@MainActor
struct OccurrenceRow: View {
    @Environment(AppModel.self) private var model
    let occurrence: ResolvedOccurrence
    let now: Date
    let onEdit: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            completionControl
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.displayTitle)
                    .strikethrough(occurrence.state == .done)
                    .foregroundStyle(occurrence.state == .done ? .secondary : .primary)
                subtitle
            }
            Spacer(minLength: 0)
            if occurrence.item.settings.priority == .mandatory {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("a11y.mandatory")
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .trailing) {
            if occurrence.item.settings.alerting.snoozeAllowed && occurrence.state.isOutstanding {
                Button("action.snooze", systemImage: "moon.zzz") {
                    model.snooze(occurrence, now: now)
                }
                .tint(.purple)
            }
        }
        .swipeActions(edge: .leading) {
            if occurrence.canStart {
                Button("action.start", systemImage: "play.fill") {
                    model.start(occurrence, now: now)
                }
                .tint(.blue)
            }
        }
    }

    private var completionControl: some View {
        Button {
            if occurrence.state == .done {
                model.reopen(occurrence)
            } else {
                model.complete(occurrence, now: now)
            }
        } label: {
            Image(systemName: completionSymbol)
                .font(.title2)
                .foregroundStyle(occurrence.state == .done ? Color.green : occurrence.state.tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(occurrence.state == .done ? "a11y.markNotDone" : "a11y.markDone")
        .accessibilityValue(Text(occurrence.state.label))
    }

    private var completionSymbol: String {
        if occurrence.state == .done { return "checkmark.circle.fill" }
        if let quota = occurrence.quotaProgress, quota.completed > 0 { return "circle.dotted" }
        return "circle"
    }

    @ViewBuilder
    private var subtitle: some View {
        HStack(spacing: 6) {
            if let quota = occurrence.quotaProgress {
                Text(verbatim: "\(quota.completed)/\(quota.target)")
                if quota.isBehindPace {
                    Text("label.behindPace")
                        .foregroundStyle(.orange)
                }
            } else if let trigger = occurrence.effectiveTrigger {
                Text(Formatting.dayAndTime(trigger, relativeTo: now))
                if occurrence.state == .active, let end = occurrence.windowEnd {
                    Text("label.endsIn \(Formatting.countdown(to: end, from: now))")
                }
            } else if occurrence.canStart {
                Text("label.notStarted")
            }

            if occurrence.state == .overdue || occurrence.state == .snoozed {
                Text(occurrence.state.label)
                    .foregroundStyle(occurrence.state.tint)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

extension ResolvedOccurrence {
    /// A relative timer the user has not started yet.
    var canStart: Bool {
        item.settings.trigger.kind == .relative && record.startedAt == nil && state.isOutstanding
    }
}

#Preview {
    PreviewHost { TodayView() }
}
