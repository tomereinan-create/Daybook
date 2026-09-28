import SwiftData
import SwiftUI

/// The weekly review. The only place Someday items appear, and the only place
/// a Waiting-for item gets chased.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Query private var items: [Item]
    @State private var now = Date.now
    @State private var editing: Item?

    var body: some View {
        NavigationStack {
            Group {
                if review.hasAnythingToSay {
                    list
                } else {
                    ContentUnavailableView(
                        "review.empty.title",
                        systemImage: "calendar",
                        description: Text("review.empty.description")
                    )
                }
            }
            .navigationTitle("review.title")
            .sheet(item: $editing) { item in
                NavigationStack { ItemEditorView(item: item) }
            }
        }
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var review: WeekReview {
        _ = items.count
        _ = model.revision
        return model.weekReview(now: now)
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Tally(value: review.completed, caption: "review.done", tint: .primary)
                    Tally(value: review.missed, caption: "review.missed", tint: .red)
                    Tally(value: review.behind.count, caption: "review.behind", tint: .orange)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            if !review.behind.isEmpty {
                Section("review.behind.title") {
                    ForEach(review.behind) { occurrence in
                        HStack {
                            Text(occurrence.title)
                            Spacer()
                            if let quota = occurrence.quotaProgress {
                                Text(verbatim: "\(quota.completed)/\(quota.target)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            if !review.waiting.isEmpty {
                Section("review.waiting.title") {
                    ForEach(review.waiting) { waiting in
                        Button {
                            editing = model.store.item(with: waiting.item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(waiting.item.title)
                                    .foregroundStyle(.primary)
                                Text("review.waiting.days \(waiting.daysQuiet)")
                                    .font(.caption)
                                    .foregroundStyle(waiting.isOverdue ? Color.red : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !review.someday.isEmpty {
                Section {
                    ForEach(review.someday) { snapshot in
                        HStack {
                            Text(snapshot.title)
                            Spacer()
                            Button("review.promote") {
                                promote(snapshot)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("review.someday.title")
                } footer: {
                    Text("review.someday.footer")
                }
            }
        }
    }

    /// Someday to Task: the item keeps its history and simply starts being
    /// shown, rather than being recreated as something new.
    private func promote(_ snapshot: ItemSnapshot) {
        guard let item = model.store.item(with: snapshot.id) else { return }
        var settings = PresetKind.task.defaultSettings(reference: .now, calendar: .current)
        settings.priority = snapshot.settings.priority
        settings.steps = snapshot.settings.steps
        item.preset = .task
        model.update(item, title: item.title, notes: item.notes, settings: settings)
    }
}

private struct Tally: View {
    let value: Int
    let caption: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.title.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PreviewHost { ReviewView() }
}
