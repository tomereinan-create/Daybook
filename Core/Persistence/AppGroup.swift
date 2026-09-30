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
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8))
        else { return [] }

        let plistData = data[start.lowerBound..<end.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
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

/// What this particular install actually contains.
///
/// Not everything that was built necessarily arrives on the phone. A
/// sideloading tool working from a free Apple account may drop the app
/// extension, because every extension needs its own App ID and a free account
/// is allowed ten in total. When that happens the app itself is perfect and
/// both surfaces are impossible: there is no widget to add and nothing to
/// draw the lock-screen card with.
nonisolated enum InstalledBundle {
    static var hasWidgetExtension: Bool {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: plugIns,
                  includingPropertiesForKeys: nil
              )
        else { return false }
        return contents.contains { $0.pathExtension == "appex" }
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

    static var onboardingComplete: Bool {
        get { store.bool(forKey: Key.onboardingComplete) }
        set { store.set(newValue, forKey: Key.onboardingComplete) }
    }
}
