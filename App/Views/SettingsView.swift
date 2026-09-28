import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var quietHours = SharedDefaults.quietHours
    @State private var showsWidgetHelp = false
    @State private var showsPushSetup = false

    var body: some View {
        NavigationStack {
            Form {
                quietHoursSection
                permissionsSection
                widgetSection
                pushSection
                diagnosticsSection
                privacySection
            }
            .navigationTitle("settings.title")
            .sheet(isPresented: $showsWidgetHelp) { WidgetSetupView() }
            .sheet(isPresented: $showsPushSetup) { PushSetupView() }
        }
    }

    // MARK: - Quiet hours

    private var quietHoursSection: some View {
        Section {
            Toggle("settings.quiet.enabled", isOn: enabledBinding)
            if quietHours.isEnabled {
                DatePicker("settings.quiet.from", selection: startBinding, displayedComponents: .hourAndMinute)
                DatePicker("settings.quiet.until", selection: endBinding, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("settings.quiet.title")
        } footer: {
            Text("settings.quiet.footer")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { quietHours.isEnabled },
            set: { quietHours.isEnabled = $0; commitQuietHours() }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(setting: quietHours.start, on: .now) ?? .now },
            set: { quietHours.start = Calendar.current.timeOfDay(of: $0); commitQuietHours() }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(setting: quietHours.end, on: .now) ?? .now },
            set: { quietHours.end = Calendar.current.timeOfDay(of: $0); commitQuietHours() }
        )
    }

    private func commitQuietHours() {
        model.updateQuietHours(quietHours)
    }

    // MARK: - Permissions
    //
    // Every one of these can be refused, and the app has to keep working when
    // it is. Each row says what is lost and what to do about it, rather than
    // asking again in a loop the system will never show.

    private var permissionsSection: some View {
        Section {
            PermissionRow(
                title: "settings.permission.notifications",
                status: model.lastSchedule.notificationAuthorization.label,
                isGranted: model.lastSchedule.notificationAuthorization.canPost,
                consequence: "settings.permission.notifications.denied"
            )
            PermissionRow(
                title: "settings.permission.alarms",
                status: model.lastSchedule.alarmAuthorization.label,
                isGranted: model.lastSchedule.alarmAuthorization.canSchedule,
                consequence: "settings.permission.alarms.denied"
            )
            PermissionRow(
                title: "settings.permission.location",
                status: model.locationAuthorization.label,
                isGranted: model.locationAuthorization.canMonitor,
                consequence: "settings.permission.location.denied"
            )

            if !model.unmonitoredPlaces.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("location.overflow.title")
                            .font(.subheadline.weight(.semibold))
                        Text("location.overflow.body \(model.unmonitoredPlaces.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Button("settings.permission.open") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("settings.permission.title")
        } footer: {
            Text("settings.permission.footer")
        }
    }

    // MARK: - The widget

    private var widgetSection: some View {
        Section {
            Button {
                showsWidgetHelp = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.widget.title")
                        .foregroundStyle(.primary)
                    Text("settings.widget.subtitle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Push

    private var pushSection: some View {
        Section {
            Button {
                showsPushSetup = true
            } label: {
                HStack {
                    Text("settings.push.title")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(SharedDefaults.isPushConfigured ? "settings.push.on" : "settings.push.off")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("settings.push.footer")
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            LabeledContent("settings.diag.scheduled") {
                Text(verbatim: "\(model.lastSchedule.added + model.lastSchedule.kept)")
            }
            if model.lastSchedule.droppedByBudget > 0 {
                LabeledContent("settings.diag.dropped") {
                    Text(verbatim: "\(model.lastSchedule.droppedByBudget)")
                }
            }
            if model.store.isUsingFallbackStore {
                Label("settings.diag.fallbackStore", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("settings.diag.title")
        } footer: {
            Text("settings.diag.footer")
        }
    }

    private var privacySection: some View {
        Section {
            Label("settings.privacy.body", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let status: LocalizedStringKey
    let isGranted: Bool
    let consequence: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(isGranted ? Color.green : Color.secondary)
            }
            if !isGranted {
                Text(consequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

nonisolated extension NotificationAuthorization {
    var label: LocalizedStringKey {
        switch self {
        case .authorized: "permission.allowed"
        case .provisional: "permission.quiet"
        case .denied: "permission.denied"
        case .notDetermined: "permission.notAsked"
        }
    }
}

nonisolated extension AlarmAuthorization {
    var label: LocalizedStringKey {
        switch self {
        case .authorized: "permission.allowed"
        case .denied: "permission.denied"
        case .notDetermined: "permission.notAsked"
        }
    }
}

nonisolated extension LocationAuthorization {
    var label: LocalizedStringKey {
        switch self {
        case .always: "permission.allowed"
        case .whenInUse: "permission.whenInUse"
        case .denied: "permission.denied"
        case .notDetermined: "permission.notAsked"
        }
    }
}

#Preview {
    PreviewHost { SettingsView() }
}
