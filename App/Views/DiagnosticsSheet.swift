import SwiftUI
import UIKit

/// Everything the app can find out about its own install, on one screen, with
/// a button that puts it on the clipboard.
///
/// This exists because describing a symptom over a chat costs several rounds
/// and still leaves the answer ambiguous — which build is this, is the
/// extension signed, which App Group was it actually granted. One tap and a
/// paste settles all of it at once. It is reached from the notice on Today as
/// well as from Settings, because the notice is where somebody already is when
/// they want to know.
struct DiagnosticsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var diagnostics = Diagnostics()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("diag.build") {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(
                                    red: BuildColor.red,
                                    green: BuildColor.green,
                                    blue: BuildColor.blue
                                ))
                                .frame(width: 14, height: 14)
                            Text(verbatim: BuildColor.name)
                        }
                    }
                } footer: {
                    Text("diag.build.footer")
                }

                Section {
                    Text(verbatim: DiagnosticsReport.text(diagnostics))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("diag.report")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = DiagnosticsReport.text(diagnostics)
                        copied = true
                    } label: {
                        Label(
                            copied ? "diag.copied" : "diag.copy",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }
                }
            }
            .navigationTitle("diag.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .task { diagnostics = await model.diagnostics() }
        }
    }
}

/// The same facts as plain text, for pasting somewhere else.
///
/// Deliberately not localized: it is read by whoever is being asked for help,
/// not by the person holding the phone.
nonisolated enum DiagnosticsReport {
    static func text(_ d: Diagnostics) -> String {
        func yes(_ value: Bool) -> String { value ? "yes" : "NO" }

        var lines: [String] = []
        lines.append("Daybook — \(BuildColor.name) (#\(BuildColor.hex))")
        lines.append("")
        lines.append("notifications:      \(d.notifications.rawValue)")
        lines.append("alerts held by iOS: \(d.pendingWithSystem)")
        lines.append("live activities on: \(yes(d.liveActivitiesEnabled))")
        lines.append("card running:       \(yes(d.liveActivityRunning))")
        if let error = d.liveActivityError {
            lines.append("card refused:       \(error)")
        }
        lines.append("")
        lines.append("widget extension:   \(yes(d.hasWidgetExtension))")
        lines.append("  signed:           \(yes(d.widgetExtensionIsSigned))")
        lines.append("  nested under app: \(yes(d.widgetExtensionIsNested))")
        lines.append("  same team as app: \(yes(d.widgetProfileMatchesApp))")
        lines.append("app bundle id:      \(d.appIdentifier)")
        lines.append("widget bundle id:   \(d.widgetIdentifier ?? "none")")
        lines.append("app profile:        \(describe(d.appProfile))")
        lines.append("widget profile:     \(describe(d.widgetProfile))")
        lines.append("")
        lines.append("shared container:   \(yes(d.hasSharedContainer))")
        lines.append("  opening:          \(d.appGroup)")
        lines.append("  signed with:      \(d.grantedGroups.isEmpty ? "none" : d.grantedGroups.joined(separator: ", "))")
        lines.append("")
        lines.append("lock-screen summary:\(d.lockScreenSummary ? "on" : "off")")
        lines.append("")
        lines.append("today:              \(d.itemsToday) items")
        lines.append("  on lock screen:   \(d.onLockScreen)")
        lines.append("  on home widget:   \(d.onHomeWidget)")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ profile: ProvisioningProfile?) -> String {
        guard let profile else { return "none — this bundle carries no profile" }
        var parts: [String] = [profile.applicationIdentifier ?? "no application-identifier"]
        if profile.hasExpired { parts.append("EXPIRED") }
        else if let expires = profile.expiresAt {
            let days = Int(expires.timeIntervalSinceNow / 86_400)
            parts.append("\(days)d left")
        }
        return parts.joined(separator: ", ")
    }
}
