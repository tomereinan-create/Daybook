import Foundation

/// The one place the App Group identifier is read.
///
/// The value comes from the target's Info.plist (`AppGroupIdentifier`), which
/// XcodeGen fills from the `APP_GROUP_ID` build setting, so the app, the widget
/// extension and the tests can never drift apart.
nonisolated enum AppGroup {
    /// The group this build can actually open, which is not always the one it
    /// was compiled with.
    ///
    /// A re-signing tool cannot register `group.com.tomereinan.daybook` on a
    /// free Apple account, so it may grant a substitute name of its own. The
    /// compiled-in name then opens nothing, and the widgets look empty for a
    /// reason no amount of checking the compiled-in name would ever find. So
    /// the signature is asked which groups it was given, and a granted one
    /// wins over an assumed one.
    ///
    /// The app and the extension are signed together, so both reach the same
    /// answer as long as the choice between several is deterministic.
    static let identifier: String = {
        let declared = (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallbackIdentifier
        return resolve(declared: declared, granted: entitledGroups)
    }()

    /// The choice, separated from where the two inputs come from so it can be
    /// tested without a bundle or a signature.
    static func resolve(declared: String, granted: [String]) -> String {
        // Nothing granted means nothing to correct: an unsigned simulator
        // build knows its own name better than an empty list does.
        if granted.isEmpty || granted.contains(declared) { return declared }
        // Sorted, so the app and the extension pick the same one.
        return granted.sorted().first ?? declared
    }

    /// The app groups named in this build's own provisioning profile.
    ///
    /// Read from the profile embedded in the bundle rather than guessed. The
    /// profile is a signed blob wrapping an XML plist; only the plist is
    /// wanted, and reading your own bundle needs no permission.
    static let entitledGroups: [String] = {
        ProvisioningProfile.read(in: Bundle.main.bundleURL)?.appGroups ?? []
    }()

    /// Used by the test bundle, which has no app Info.plist of its own.
    static let fallbackIdentifier = "group.com.tomereinan.daybook"

    /// The shared container, or `nil` when the entitlement is missing. Callers
    /// fall back to a local store rather than crashing, so a misconfigured
    /// build still runs.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var storeURL: URL? {
        containerURL?.appending(path: "Daybook.store")
    }
}

/// One bundle's embedded provisioning profile.
///
/// The profile is a signed blob wrapping an XML plist; only the plist is
/// wanted, and reading it out of a bundle the process already owns needs no
/// permission. The app and its extension each carry their own, and when a
/// re-signing tool gets one of them wrong this is the only place that says so.
nonisolated struct ProvisioningProfile: Sendable, Hashable {
    /// `TEAMID.com.example.app`. The prefix is the team the bundle was signed
    /// by; an extension signed by a different team than its host is refused.
    var applicationIdentifier: String?
    var appGroups: [String]
    var teamIdentifier: String?
    var expiresAt: Date?

    var hasExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < .now
    }

    static func read(in bundleURL: URL) -> ProvisioningProfile? {
        let url = bundleURL.appending(path: "embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        let entitlements = plist["Entitlements"] as? [String: Any]
        return ProvisioningProfile(
            applicationIdentifier: entitlements?["application-identifier"] as? String,
            appGroups: entitlements?["com.apple.security.application-groups"] as? [String] ?? [],
            teamIdentifier: (plist["TeamIdentifier"] as? [String])?.first,
            expiresAt: plist["ExpirationDate"] as? Date
        )
    }
}

/// What this particular install actually contains.
///
/// Not everything that was built necessarily arrives on the phone. A
/// sideloading tool working from a free Apple account may drop the app
/// extension, because every extension needs its own App ID and a free account
/// is allowed ten in total. When that happens the app itself is perfect and
/// both surfaces are impossible: there is no widget to add and nothing to
/// draw the lock-screen card with.
nonisolated enum InstalledBundle {
    /// The bundle identifier of the widget extension inside this install, if
    /// there is one at all.
    static let widgetExtensionIdentifier: String? = {
        widgetExtensionURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }()

    static var hasWidgetExtension: Bool { widgetExtensionURL != nil }

    static let widgetExtensionURL: URL? = {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: plugIns,
                  includingPropertiesForKeys: nil
              )
        else { return nil }
        return contents.first { $0.pathExtension == "appex" }
    }()

    /// Whether the extension carries a code signature at all.
    ///
    /// A re-signing tool can leave an extension in the bundle and sign only
    /// the app around it. The file is then plainly there — which is all the
    /// check above can see — and iOS refuses to register it, so there is no
    /// widget in the gallery and no lock-screen card, with the app itself
    /// working perfectly.
    static var widgetExtensionIsSigned: Bool {
        guard let url = widgetExtensionURL else { return false }
        return FileManager.default.fileExists(
            atPath: url.appending(path: "_CodeSignature/CodeResources").path
        )
    }

    static let appProfile: ProvisioningProfile? = ProvisioningProfile.read(in: Bundle.main.bundleURL)

    static let widgetProfile: ProvisioningProfile? = {
        guard let url = widgetExtensionURL else { return nil }
        return ProvisioningProfile.read(in: url)
    }()

    /// An extension signed by a different team than its host is refused, and
    /// so is one with no profile of its own.
    static var widgetProfileMatchesApp: Bool {
        guard let app = appProfile?.teamIdentifier,
              let widget = widgetProfile?.teamIdentifier
        else { return false }
        return app == widget
    }

    /// Whether the extension's identifier still sits underneath the app's.
    ///
    /// iOS requires it: an extension is registered as a child of its host, and
    /// one whose identifier is not `<app>.something` is refused outright. A
    /// re-signing tool that gives the app a new identifier — which free
    /// signing often does, to get a name it is allowed to register — and
    /// leaves the extension's alone breaks exactly this. The app installs and
    /// runs perfectly; the widget simply never appears in the gallery, with
    /// nothing anywhere to say why.
    static var widgetExtensionIsNested: Bool {
        guard let app = Bundle.main.bundleIdentifier,
              let extensionID = widgetExtensionIdentifier
        else { return false }
        return extensionID.hasPrefix(app + ".")
    }

    /// The choice, apart from the bundle, so it can be tested.
    static func isNested(app: String, extensionID: String) -> Bool {
        extensionID.hasPrefix(app + ".")
    }
}

/// Small shared flags the widget reads without opening the store.
nonisolated enum SharedDefaults {
    static var store: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    enum Key {
        static let quietHours = "quietHours"
        static let defaultLeadTime = "defaultLeadTime"
        static let onboardingComplete = "onboardingComplete"
        static let lastScheduleRefresh = "lastScheduleRefresh"
        static let lockScreenSummary = "lockScreenSummary"
        static let lastPostedSummary = "lastPostedSummary"
    }

    static var quietHours: QuietHours {
        get {
            guard let data = store.data(forKey: Key.quietHours),
                  let decoded = try? JSONDecoder().decode(QuietHours.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            store.set(data, forKey: Key.quietHours)
        }
    }

    /// Whether to hold the day on the lock screen as a standing notification.
    /// Off unless asked for: it is the fallback for an install whose widgets
    /// cannot work, not a second copy of them.
    static var lockScreenSummary: Bool {
        get { store.bool(forKey: Key.lockScreenSummary) }
        set { store.set(newValue, forKey: Key.lockScreenSummary) }
    }

    /// What the lock screen is currently showing, so an unchanged day is not
    /// posted again. The post lights the screen, so doing it on every
    /// reschedule — which is every change, every launch and every background
    /// refresh — would be its own kind of broken.
    static var lastPostedSummary: String? {
        get { store.string(forKey: Key.lastPostedSummary) }
        set { store.set(newValue, forKey: Key.lastPostedSummary) }
    }

    static var onboardingComplete: Bool {
        get { store.bool(forKey: Key.onboardingComplete) }
        set { store.set(newValue, forKey: Key.onboardingComplete) }
    }
}
