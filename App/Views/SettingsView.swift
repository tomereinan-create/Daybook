import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var quietHours = SharedDefaults.quietHours
    @State private var showsWidgetHelp = false
    @State private var showsPushSetup = false
    @State private var exportURL: URL?
    @State private var showsImporter = false
    @State private var transferMessage: String?
    @State private var diagnostics = Diagnostics()

    var body: some View {
        NavigationStack {
            Form {
                quietHoursSection
                permissionsSection
                widgetSection
                pushSection
                dataSection
                diagnosticsSection
                privacySection
            }
            .navigationTitle("settings.title")
            .task { await loadDiagnostics() }
            .refreshable { await loadDiagnostics() }
            .sheet(isPresented: $showsWidgetHelp) { WidgetSetupView() }
            .sheet(isPresented: $showsPushSetup) { PushSetupView() }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.json]
            ) { result in
                restore(from: result)
            }
            .alert("settings.data.result", isPresented: .constant(transferMessage != nil)) {
                Button("action.done") { transferMessage = nil }
            } message: {
                Text(transferMessage ?? "")
            }
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
                status: diagnostics.notifications.label,
                isGranted: diagnostics.notifications.canPost,
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

            // iOS shows the prompt once, ever. Until it has been shown the
            // app does not appear in the system's notification list at all,
            // so "open iOS Settings" is advice that leads nowhere — which is
            // exactly where anyone who skipped the welcome screen ended up.
            if diagnostics.notifications == .notDetermined {
                Button("settings.permission.ask") {
                    Task {
                        await model.requestPermissions()
                        await loadDiagnostics()
                    }
                }
                .fontWeight(.semibold)
            }

            Button("settings.test.send") {
                Task {
                    let status = await model.sendTestNotification()
                    transferMessage = String(
                        localized: status.canPost ? "settings.test.sent" : "settings.test.blocked"
                    )
                    await loadDiagnostics()
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

    // MARK: - Data
    //
    // There is no account and no server, so a backup is the only thing between
    // a reinstall and losing everything — and a sideloaded build has to be
    // reinstalled every seven days.

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("settings.data.share", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                prepareExport()
            } label: {
                Label(
                    exportURL == nil ? "settings.data.export" : "settings.data.exportAgain",
                    systemImage: "arrow.down.document"
                )
            }
            Button {
                showsImporter = true
            } label: {
                Label("settings.data.restore", systemImage: "arrow.up.document")
            }
        } header: {
            Text("settings.data.title")
        } footer: {
            Text("settings.data.footer")
        }
    }

    private func prepareExport() {
        do {
            exportURL = try model.exportData()
        } catch {
            transferMessage = String(localized: "settings.data.exportFailed")
        }
    }

    /// Restoring replaces everything. Merging two histories of the same item
    /// would silently invent a third.
    private func restore(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            let count = try model.restoreData(from: data)
            transferMessage = String(localized: "settings.data.restored \(count)")
        } catch {
            transferMessage = String(localized: "settings.data.restoreFailed")
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            // Which build this is. The icon on the home screen is the same
            // colour, so this row and a glance at the app agree or the
            // install did not take.
            LabeledContent("settings.diag.build") {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(
                            red: BuildColor.red,
                            green: BuildColor.green,
                            blue: BuildColor.blue
                        ))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    Text(verbatim: BuildColor.name)
                }
            }

            // Read from iOS, not from what the last reschedule believed. When
            // a surface is silent the useful question is which link in the
            // chain gave way, and each row here is one link.
            DiagnosticRow(
                title: "settings.diag.permission",
                value: Text(diagnostics.notifications.label),
                isGood: diagnostics.notifications.canPost
            )
            DiagnosticRow(
                title: "settings.diag.heldByIOS",
                value: Text(verbatim: "\(diagnostics.pendingWithSystem)"),
                isGood: diagnostics.pendingWithSystem > 0 || !diagnostics.notifications.canPost
            )
            if diagnostics.notifications.canPost && diagnostics.pendingWithSystem == 0 {
                Text("settings.diag.noneHeld")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.lastSchedule.droppedByBudget > 0 {
                LabeledContent("settings.diag.dropped") {
                    Text(verbatim: "\(model.lastSchedule.droppedByBudget)")
                }
            }

            DiagnosticRow(
                title: "settings.diag.liveActivities",
                value: allowedOrNot(diagnostics.liveActivitiesEnabled),
                isGood: diagnostics.liveActivitiesEnabled
            )
            DiagnosticRow(
                title: "settings.diag.cardRunning",
                value: yesOrNo(diagnostics.liveActivityRunning),
                isGood: diagnostics.liveActivityRunning || diagnostics.onLockScreen == 0
            )
            if let error = diagnostics.liveActivityError {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            DiagnosticRow(
                title: "settings.diag.onLockScreen",
                value: Text(verbatim: "\(diagnostics.onLockScreen)"),
                isGood: diagnostics.onLockScreen > 0
            )
            DiagnosticRow(
                title: "settings.diag.onHomeWidget",
                value: Text(verbatim: "\(diagnostics.onHomeWidget)"),
                isGood: diagnostics.onHomeWidget > 0
            )
            if diagnostics.onLockScreen == 0 && diagnostics.onHomeWidget == 0 {
                Text("settings.diag.nothingShared")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DiagnosticRow(
                title: "settings.diag.widgetExtension",
                value: yesOrNo(diagnostics.hasWidgetExtension),
                isGood: diagnostics.hasWidgetExtension
            )
            // Printed whether or not anything is wrong: these two names are
            // the evidence, and reading them back is quicker than describing
            // a symptom.
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.diag.appIdentifier")
                Text(verbatim: diagnostics.appIdentifier)
                    .foregroundStyle(.secondary)
                Text("settings.diag.widgetIdentifier")
                if let widgetIdentifier = diagnostics.widgetIdentifier {
                    Text(verbatim: widgetIdentifier)
                        .foregroundStyle(
                            diagnostics.widgetExtensionIsNested ? Color.secondary : Color.orange
                        )
                } else {
                    Text("settings.diag.widgetIdentifierNone")
                        .foregroundStyle(Color.orange)
                }
            }
            .font(.caption2.monospaced())
            .textSelection(.enabled)

            DiagnosticRow(
                title: "settings.diag.sharedContainer",
                value: yesOrNo(diagnostics.hasSharedContainer),
                isGood: diagnostics.hasSharedContainer
            )
            if !diagnostics.hasSharedContainer {
                Text("settings.diag.fallbackStore")
                    .font(.caption)
                    .foregroundStyle(.orange)
                // The exact names, because the interesting case is a signature
                // that grants a group under a name nobody expected.
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.diag.groupWanted \(diagnostics.appGroup)")
                    Text(
                        diagnostics.grantedGroups.isEmpty
                            ? String(localized: "settings.diag.groupNone")
                            : String(
                                localized: "settings.diag.groupGranted \(diagnostics.grantedGroups.joined(separator: ", "))"
                            )
                    )
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        } header: {
            Text("settings.diag.title")
        } footer: {
            Text("settings.diag.footer")
        }
    }

    private func loadDiagnostics() async {
        diagnostics = await model.diagnostics()
    }

    // Spelled out rather than written as a ternary of two string literals:
    // that form can resolve to `String`, which puts the key itself on screen.
    private func yesOrNo(_ value: Bool) -> Text {
        value ? Text("settings.diag.yes") : Text("settings.diag.no")
    }

    private func allowedOrNot(_ value: Bool) -> Text {
        value ? Text("permission.allowed") : Text("permission.denied")
    }

    private var privacySection: some View {
        Section {
            Label("settings.privacy.body", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// One fact, with a tick or a cross. Deliberately plain: this screen exists to
/// be read out to somebody who cannot see the phone.
private struct DiagnosticRow: View {
    let title: LocalizedStringKey
    let value: Text
    let isGood: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                value
                Image(systemName: isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isGood ? Color.green : Color.orange)
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
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
