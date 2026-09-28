import SwiftUI

/// Which presets the create flow offers.
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
        .locationReminder,
        .wakeUp,
        .waitingFor,
        .someday
    ]
}

/// Step one of creating an item: pick the shape, then edit only what matters.
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
