import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Re-reading these keeps the plan fresh when SwiftData changes underneath.
    @Query private var items: [Item]
    @Query private var records: [OccurrenceRecord]

    @State private var now = Date.now
    @State private var creating = false
    @State private var editing: Item?
    @State private var diagnostics = Diagnostics()
    /// Notices the user has put away, kept across launches. Only the ones
    /// they cannot act on from here can end up in this list.
    @AppStorage("dismissedNotices") private var dismissedNotices = ""
    @State private var showsDiagnostics = false

    private let sectionOrder: [DaySection] = [.now, .upcoming, .undated, .done, .missed]

    var body: some View {
        // Resolved once per render and handed down. Reading `currentPlan` in
        // each branch would run the engine over the whole lookback window six
        // times for one pass of the screen.
        let plan = currentPlan

        return NavigationStack {
            VStack(spacing: 0) {
                // Whatever is stopping the app from reaching a surface belongs
                // here, on the screen that is open anyway — not in Settings,
                // where it can only be found by somebody who already suspects
                // something is wrong.
                if let notice = visibleNotice {
                    SetupNoticeBanner(
                        notice: notice,
                        onAsk: {
                            await model.requestPermissions()
                            await loadDiagnostics()
                        },
                        onUseLockScreen: {
                            SharedDefaults.lockScreenSummary = true
                            Task {
                                await model.reschedule()
                                await loadDiagnostics()
                            }
                        },
                        onDismiss: { dismiss(notice) },
                        onInspect: { showsDiagnostics = true }
                    )
                }

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
            .sheet(isPresented: $showsDiagnostics) {
                DiagnosticsSheet()
            }
        }
        // The + on the home screen widget.
        .onOpenURL { url in
            if url.scheme == "daybook", url.host() == "new" {
                creating = true
            }
        }
        .task {
            await loadDiagnostics()
            // One cheap tick keeps countdowns and state transitions honest
            // without a timer that fires while the app is backgrounded.
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // What is on a surface changes when the items do.
        .onChange(of: model.revision) {
            Task { await loadDiagnostics() }
        }
    }

    private var visibleNotice: SetupNotice? {
        guard let notice = SetupNotice.first(from: diagnostics) else { return nil }
        return dismissedNotices.contains(notice.id) ? nil : notice
    }

    private func dismiss(_ notice: SetupNotice) {
        guard notice.isDismissible else { return }
        dismissedNotices += "\(notice.id),"
    }

    private func loadDiagnostics() async {
        diagnostics = await model.diagnostics(now: .now)
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
struct OccurrenceRow: View {
    @Environment(AppModel.self) private var model
    let occurrence: ResolvedOccurrence
    let now: Date
    let onEdit: @MainActor () -> Void
    @State private var pendingDelete = false
    @State private var askingForAnswer = false
    @State private var answerDraft = ""

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
        // An item that asks for an answer asks for it here, at the moment it
        // is finished, rather than making the user open the editor to record
        // a number they already have in their head.
        .alert(answerPrompt, isPresented: $askingForAnswer) {
            TextField("field.answer", text: $answerDraft)
                .keyboardType(
                    occurrence.item.settings.answerKind == .number ? .decimalPad : .default
                )
            Button("action.save") {
                model.complete(occurrence, now: now, answer: answerDraft)
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text(occurrence.displayTitle)
        }
        // Three answers to every row: I did it, I did not, and get rid of it.
        // Swipe for speed, long press for the ones you use less often.
        .swipeActions(edge: .trailing) {
            Button("action.delete", systemImage: "trash", role: .destructive) {
                pendingDelete = true
            }
            if occurrence.state != .missed {
                Button("action.notDone", systemImage: "xmark") {
                    model.markNotDone(occurrence, now: now)
                }
                .tint(.orange)
            }
            if occurrence.item.settings.alerting.snoozeAllowed && occurrence.state.isOutstanding {
                Button("action.snooze", systemImage: "moon.zzz") {
                    model.snooze(occurrence, now: now)
                }
                .tint(.purple)
            }
        }
        .swipeActions(edge: .leading) {
            if occurrence.state == .done || occurrence.state == .missed {
                Button("action.notDoneUndo", systemImage: "arrow.uturn.backward") {
                    model.reopen(occurrence)
                }
                .tint(.gray)
            } else {
                Button("action.done", systemImage: "checkmark") {
                    done()
                }
                .tint(.green)
            }
            if occurrence.canStart {
                Button("action.start", systemImage: "play.fill") {
                    model.start(occurrence, now: now)
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if occurrence.state != .done {
                Button("action.done", systemImage: "checkmark.circle") {
                    done()
                }
            }
            if occurrence.state != .missed {
                Button("action.notDone", systemImage: "xmark.circle") {
                    model.markNotDone(occurrence, now: now)
                }
            }
            if occurrence.state == .done || occurrence.state == .missed {
                Button("action.notDoneUndo", systemImage: "arrow.uturn.backward") {
                    model.reopen(occurrence)
                }
            }
            Button("action.edit", systemImage: "pencil", action: onEdit)
            Divider()
            Button("action.delete", systemImage: "trash", role: .destructive) {
                pendingDelete = true
            }
        }
        .confirmationDialog(
            occurrence.item.settings.recurrence.frequency.repeats
                ? "delete.recurring.confirm"
                : "delete.confirm",
            isPresented: $pendingDelete,
            titleVisibility: .visible
        ) {
            Button("action.delete", role: .destructive) {
                model.deleteItem(of: occurrence)
            }
            Button("action.cancel", role: .cancel) {}
        }
    }

    private var completionControl: some View {
        Button {
            if occurrence.state == .done {
                model.reopen(occurrence)
            } else {
                done()
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

    private var answerPrompt: LocalizedStringKey {
        // Written out rather than as a ternary of two literals: that form can
        // resolve to String and put the key itself on screen.
        if occurrence.item.settings.answerKind == .number {
            return "answer.prompt.number"
        }
        return "answer.prompt.text"
    }

    /// Done either finishes the thing or starts its clock; either way the tap
    /// is the same, and an item that wants an answer asks for one first.
    private func done() {
        guard occurrence.item.settings.answerKind.asksForAnything,
              occurrence.state.isOutstanding
        else {
            model.complete(occurrence, now: now)
            return
        }
        answerDraft = occurrence.record.answer ?? ""
        askingForAnswer = true
    }

    @ViewBuilder
    private var subtitle: some View {
        HStack(spacing: 6) {
            // A running hold is the only thing worth saying while it runs.
            if let hold = occurrence.record.holdUntil, hold > now {
                Text("label.stopIn \(Formatting.countdown(to: hold, from: now))")
                    .foregroundStyle(.blue)
            } else if let answer = occurrence.record.answer, !answer.isEmpty {
                Text(verbatim: answer)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            } else if let quota = occurrence.quotaProgress {
                Text(verbatim: "\(quota.completed)/\(quota.target)")
                if quota.isBehindPace {
                    Text("label.behindPace")
                        .foregroundStyle(.orange)
                }
            } else if let trigger = occurrence.effectiveTrigger {
                Text(Formatting.dayAndTime(trigger, relativeTo: now))
                // A time block counts down to the end of its window; a running
                // timer counts down to the moment it goes off.
                if occurrence.state == .active, let end = occurrence.windowEnd ?? occurrence.effectiveTrigger, end > now {
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
    /// A countdown waiting to be started by hand. One that starts itself never
    /// offers the button, because there is nothing left to press.
    var canStart: Bool {
        item.settings.trigger.kind == .relative
            && !item.settings.trigger.runsUnattended
            && record.startedAt == nil
            && state.isOutstanding
    }
}

#Preview {
    PreviewHost { TodayView() }
}
