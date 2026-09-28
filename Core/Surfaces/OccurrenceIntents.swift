import AppIntents
import Foundation
import WidgetKit

/// The identity of an occurrence, as an intent parameter.
///
/// `AppIntent` parameters have to be simple values, so the key travels as its
/// two halves and is reassembled on the other side.
nonisolated struct OccurrenceReference: Sendable {
    var itemID: String
    var slot: Double

    var key: OccurrenceKey? {
        guard let id = UUID(uuidString: itemID) else { return nil }
        return OccurrenceKey(itemID: id, slot: Date(timeIntervalSince1970: slot))
    }

    init(_ key: OccurrenceKey) {
        self.itemID = key.itemID.uuidString
        self.slot = key.slot.timeIntervalSince1970
    }
}

/// Tapping a completion circle on the home screen widget.
///
/// Runs in the widget extension with the app closed, so it does the work
/// against the shared store directly and then asks WidgetKit to redraw.
struct CompleteOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.complete.title"
    static let description = IntentDescription("intent.complete.description")
    /// The app must not be launched for a tick on a widget.
    static let openAppWhenRun = false

    @Parameter(title: "intent.param.item")
    var itemID: String

    @Parameter(title: "intent.param.slot")
    var slot: Double

    init() {}

    init(_ reference: OccurrenceReference) {
        self.itemID = reference.itemID
        self.slot = reference.slot
    }

    func perform() async throws -> some IntentResult {
        let reference = OccurrenceReference(itemID: itemID, slot: slot)
        guard let key = reference.key else { return .result() }
        await MainActor.run { _ = OccurrenceActions.complete(key) }
        await SurfaceRefresh.reloadAll()
        return .result()
    }
}

struct SnoozeOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.snooze.title"
    static let description = IntentDescription("intent.snooze.description")
    static let openAppWhenRun = false

    @Parameter(title: "intent.param.item")
    var itemID: String

    @Parameter(title: "intent.param.slot")
    var slot: Double

    init() {}

    init(_ reference: OccurrenceReference) {
        self.itemID = reference.itemID
        self.slot = reference.slot
    }

    func perform() async throws -> some IntentResult {
        let reference = OccurrenceReference(itemID: itemID, slot: slot)
        guard let key = reference.key else { return .result() }
        await MainActor.run { _ = OccurrenceActions.snooze(key) }
        await SurfaceRefresh.reloadAll()
        return .result()
    }
}

/// Starting a relative timer from a surface.
struct StartOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.start.title"
    static let description = IntentDescription("intent.start.description")
    static let openAppWhenRun = false

    @Parameter(title: "intent.param.item")
    var itemID: String

    @Parameter(title: "intent.param.slot")
    var slot: Double

    init() {}

    init(_ reference: OccurrenceReference) {
        self.itemID = reference.itemID
        self.slot = reference.slot
    }

    func perform() async throws -> some IntentResult {
        let reference = OccurrenceReference(itemID: itemID, slot: slot)
        guard let key = reference.key else { return .result() }
        await MainActor.run { _ = OccurrenceActions.start(key) }
        await SurfaceRefresh.reloadAll()
        return .result()
    }
}

nonisolated extension OccurrenceReference {
    init(itemID: String, slot: Double) {
        self.itemID = itemID
        self.slot = slot
    }
}

/// Asks every surface to redraw. Cheap, and the only correct thing to do after
/// the shared store changes: the app, the widgets and the Live Activity all
/// read the same day and must never disagree about it.
nonisolated enum SurfaceRefresh {
    static func reloadAll() async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
