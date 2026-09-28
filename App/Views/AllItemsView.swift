import SwiftData
import SwiftUI

/// Every item the user has, grouped so the ones that never reach a surface
/// are still easy to find.
@MainActor
struct AllItemsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    @State private var editing: Item?
    @State private var showsArchived = false

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "items.empty.title",
                        systemImage: "tray",
                        description: Text("items.empty.description")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("items.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("action.showArchived", systemImage: "archivebox", isOn: $showsArchived)
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(item: $editing) { item in
                NavigationStack {
                    ItemEditorView(item: item)
                }
            }
        }
    }

    private var visibleItems: [Item] {
        items.filter { showsArchived || !$0.isArchived }
    }

    private var groups: [(preset: PresetKind, items: [Item])] {
        let grouped = Dictionary(grouping: visibleItems, by: \.preset)
        return PresetKind.allCases.compactMap { preset in
            guard let members = grouped[preset], !members.isEmpty else { return nil }
            return (preset, members)
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.preset) { group in
                Section {
                    ForEach(group.items) { item in
                        Button {
                            editing = item
                        } label: {
                            ItemSummaryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label(group.preset.title, systemImage: group.preset.symbol)
                }
            }
        }
    }
}

private struct ItemSummaryRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .foregroundStyle(item.isArchived ? .secondary : .primary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let settings = item.settings
        var parts: [String] = []

        switch settings.recurrence.frequency {
        case .once:
            if let date = settings.trigger.date {
                parts.append(Formatting.dayAndTime(date, relativeTo: .now))
            }
        case .daily:
            parts.append(String(localized: "summary.daily"))
        case .weekdays(let days):
            parts.append(days.sorted().map(\.shortLabel).joined(separator: " "))
        case .everyNDays(let n):
            parts.append(String(localized: "summary.everyNDays \(n)"))
        case .dayOfMonth(let day):
            parts.append(String(localized: "summary.dayOfMonth \(day)"))
        case .quota(let count, let period):
            let periodName = period == .week
                ? String(localized: "period.week")
                : String(localized: "period.month")
            parts.append(String(localized: "summary.quota \(count) \(periodName)"))
        }

        if let time = settings.trigger.timeOfDay, settings.recurrence.frequency.repeats {
            parts.append(Formatting.time(Calendar.current.date(setting: time, on: .now) ?? .now))
        }
        if item.isArchived {
            parts.append(String(localized: "summary.archived"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    PreviewHost { AllItemsView() }
}
