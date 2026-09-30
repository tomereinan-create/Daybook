import Foundation

/// The one place the App Group identifier is read.
///
/// The value comes from the target's Info.plist (`AppGroupIdentifier`), which
/// XcodeGen fills from the `APP_GROUP_ID` build setting, so the app, the widget
/// extension and the tests can never drift apart.
nonisolated enum AppGroup {
    static let identifier: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !value.isEmpty
        else { return fallbackIdentifier }
        return value
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
