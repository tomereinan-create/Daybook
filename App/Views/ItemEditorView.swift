import SwiftData
import SwiftUI

/// Create and edit share one form. The preset decides which settings sit in
/// the open, everything else lives under Advanced, and nothing is hidden for
/// good.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    @State private var draft: ItemDraft
    @State private var showsDeleteConfirmation = false

    enum Mode {
        case create(PresetKind)
        case edit(Item)
    }

    init(creating preset: PresetKind, now: Date = .now, calendar: Calendar = .current) {
        self.mode = .create(preset)
        _draft = State(
            initialValue: ItemDraft(
                title: "",
                notes: "",
                preset: preset,
                settings: preset.defaultSettings(reference: now, calendar: calendar)
            )
        )
    }

    init(item: Item) {
        self.mode = .edit(item)
        _draft = State(
            initialValue: ItemDraft(
                title: item.title,
                notes: item.notes,
                preset: item.preset,
                settings: item.settings
            )
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("field.title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                TextField("field.notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                ForEach(orderedProminentFields, id: \.self) { field in
                    SettingFieldView(field: field, settings: $draft.settings)
                }
            } header: {
                Label(draft.preset.title, systemImage: draft.preset.symbol)
            }

            if !draft.settings.canAlert {
                Section {
                    Label("editor.silent", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(SettingGroup.allCases) { group in
                let fields = advancedFields.filter { $0.group == group }
                if !fields.isEmpty {
                    Section {
                        DisclosureGroup(group.title) {
                            ForEach(fields, id: \.self) { field in
                                SettingFieldView(field: field, settings: $draft.settings)
                            }
                        }
                    }
                }
            }

            if case .edit(let item) = mode {
                Section {
                    Button(item.isArchived ? "action.unarchive" : "action.archive") {
                        model.setArchived(item, !item.isArchived)
                        dismiss()
                    }
                    Button("action.delete", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(isCreating ? "new.details" : "edit.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.save") { save() }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isCreating {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "delete.confirm",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("action.delete", role: .destructive) {
                if case .edit(let item) = mode {
                    model.delete(item)
                }
                dismiss()
            }
            Button("action.cancel", role: .cancel) {}
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var editableFields: [SettingField] {
        SettingField.allCases
    }

    private var orderedProminentFields: [SettingField] {
        editableFields.filter { draft.preset.prominentFields.contains($0) }
    }

    private var advancedFields: [SettingField] {
        editableFields.filter { !draft.preset.prominentFields.contains($0) }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        switch mode {
        case .create(let preset):
            model.createItem(
                title: title,
                notes: draft.notes,
                preset: preset,
                settings: draft.settings
            )
        case .edit(let item):
            model.update(item, title: title, notes: draft.notes, settings: draft.settings)
        }
        dismiss()
    }
}

/// What the form is editing, kept apart from the stored item so a cancel is
/// genuinely a cancel.
struct ItemDraft {
    var title: String
    var notes: String
    var preset: PresetKind
    var settings: ItemSettings
}

#Preview {
    PreviewHost {
        NavigationStack {
            ItemEditorView(creating: .recurringTask)
        }
    }
}
