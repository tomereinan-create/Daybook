import SwiftUI

/// The one thing currently stopping the app from reaching a surface, said on
/// the first screen rather than left in Settings to be found.
///
/// Only ever one at a time, in the order they block each other: there is no
/// point explaining that the lock-screen card is switched off to somebody who
/// has not been asked about notifications yet. Fix the top one and the next
/// appears, which makes the list a sequence rather than a wall.
enum SetupNotice: String, Identifiable, CaseIterable {
    /// iOS has never shown the prompt. This is the only state the app can fix
    /// by itself, and it gets exactly one chance.
    case notificationsNeverAsked
    case notificationsDenied
    /// The extension never arrived on the phone, which makes both surfaces
    /// impossible however well everything else is set up.
    case widgetExtensionMissing
    /// Present, but under an identifier iOS will not register.
    case widgetExtensionRenamed
    /// Present and correctly named, but carrying no signature of its own.
    case widgetExtensionUnsigned
    case liveActivitiesOff
    case noSharedContainer
    case nothingOnSurfaces

    var id: String { rawValue }

    static func first(from diagnostics: Diagnostics) -> SetupNotice? {
        if diagnostics.notifications == .notDetermined { return .notificationsNeverAsked }
        if diagnostics.notifications == .denied { return .notificationsDenied }
        // Above the rest: with no extension there is nothing to switch on.
        if !diagnostics.hasWidgetExtension { return .widgetExtensionMissing }
        if !diagnostics.widgetExtensionIsNested { return .widgetExtensionRenamed }
        if !diagnostics.widgetExtensionIsSigned { return .widgetExtensionUnsigned }
        if !diagnostics.liveActivitiesEnabled { return .liveActivitiesOff }
        if !diagnostics.hasSharedContainer { return .noSharedContainer }
        if diagnostics.itemsToday > 0,
           diagnostics.onLockScreen == 0,
           diagnostics.onHomeWidget == 0 {
            return .nothingOnSurfaces
        }
        return nil
    }

    var title: LocalizedStringKey {
        switch self {
        case .notificationsNeverAsked: "notice.notifications.title"
        case .notificationsDenied: "notice.denied.title"
        case .widgetExtensionMissing: "notice.extension.title"
        case .widgetExtensionRenamed: "notice.renamed.title"
        case .widgetExtensionUnsigned: "notice.unsigned.title"
        case .liveActivitiesOff: "notice.liveActivities.title"
        case .noSharedContainer: "notice.container.title"
        case .nothingOnSurfaces: "notice.surfaces.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .notificationsNeverAsked: "notice.notifications.body"
        case .notificationsDenied: "notice.denied.body"
        case .widgetExtensionMissing: "notice.extension.body"
        case .widgetExtensionRenamed: "notice.renamed.body"
        case .widgetExtensionUnsigned: "notice.unsigned.body"
        case .liveActivitiesOff: "notice.liveActivities.body"
        case .noSharedContainer: "notice.container.body"
        case .nothingOnSurfaces: "notice.surfaces.body"
        }
    }

    var symbol: String {
        switch self {
        case .notificationsNeverAsked, .notificationsDenied: "bell.slash.fill"
        case .widgetExtensionMissing, .widgetExtensionRenamed, .widgetExtensionUnsigned:
            "square.slash"
        case .liveActivitiesOff: "lock.display"
        case .noSharedContainer: "square.grid.2x2"
        case .nothingOnSurfaces: "eye.slash"
        }
    }

    // Spelled out rather than relying on synthesis, because the tests compare
    // an optional of it.
    enum Action: Equatable {
        case ask
        case openSystemSettings
        /// Nothing about the install can be fixed from here, but the day can
        /// still reach the lock screen another way.
        case useLockScreenSummary
    }

    var action: Action? {
        switch self {
        case .notificationsNeverAsked: .ask
        case .notificationsDenied, .liveActivitiesOff: .openSystemSettings
        // None of these can be put right from inside the app — they are
        // decided by how the build was signed. What can be offered is the
        // fallback that needs neither an extension nor a shared container.
        case .widgetExtensionMissing, .widgetExtensionRenamed, .widgetExtensionUnsigned,
             .noSharedContainer:
            .useLockScreenSummary
        case .nothingOnSurfaces: nil
        }
    }

    var actionTitle: LocalizedStringKey {
        switch action {
        case .ask: "notice.notifications.action"
        case .useLockScreenSummary: "notice.useNotifications"
        default: "notice.openSettings"
        }
    }

    /// True for the ones nothing in the app can put right. Those can be put
    /// away; the ones that describe something still fixable stay until it is.
    var isDismissible: Bool {
        switch self {
        case .notificationsNeverAsked, .notificationsDenied, .liveActivitiesOff: false
        case .widgetExtensionMissing, .widgetExtensionRenamed, .widgetExtensionUnsigned,
             .noSharedContainer, .nothingOnSurfaces: true
        }
    }
}

struct SetupNoticeBanner: View {
    let notice: SetupNotice
    let onAsk: () async -> Void
    let onUseLockScreen: () -> Void
    let onDismiss: () -> Void
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notice.symbol)
                    .foregroundStyle(.orange)
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if notice.isDismissible {
                    Button("action.dismiss", systemImage: "xmark") { onDismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }

            Text(notice.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                // Whatever the notice says, the facts behind it are one tap
                // away rather than four screens away in Settings.
                Button("notice.details") { onInspect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if let action = notice.action {
                    Button(notice.actionTitle) {
                        switch action {
                        case .ask:
                            Task { await onAsk() }
                        case .openSystemSettings:
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        case .useLockScreenSummary:
                            onUseLockScreen()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }
}
