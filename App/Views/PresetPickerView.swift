import SwiftUI

/// Which presets the create flow offers today.
///
/// `locationReminder` is deliberately absent until phase 3 brings the map
/// picker: the engine handles location triggers already, but offering the
/// preset now would create items with nowhere to fire.
enum PresetCatalog {
    static let available: [PresetKind] = [
        .task,
        .event,
        .recurringTask,
        .deadlineTask,
        .timeBlock,
        .routine,
        .flexibleHabit,
        .relativeTimer,
        .wakeUp,
        .waitingFor,
        .someday
    ]
}

/// Step one of creating an item: pick the shape, then edit only what matters.
@MainActor
struct NewItemFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: PresetKind?

    var body: some View {
        NavigationStack {
            List(PresetCatalog.available) { preset in
                Button {
                    chosen = preset
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .foregroundStyle(.primary)
                            Text(preset.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: preset.symbol)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .navigationTitle("new.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $chosen) { preset in
                ItemEditorView(creating: preset)
            }
        }
    }
}

#Preview {
    PreviewHost { NewItemFlow() }
}
