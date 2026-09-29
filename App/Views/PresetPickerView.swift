import SwiftUI

/// Which presets the create flow offers.
enum PresetCatalog {
    /// Five, chosen by Tomer after using the app. The other seven kinds still
    /// exist in the model and the engine — an item created before this change
    /// keeps working, and the settings that made those kinds distinctive are
    /// all still reachable under Advanced on any item.
    static let available: [PresetKind] = [
        .task,
        .event,
        .recurringTask,
        .routine,
        .relativeTimer
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
