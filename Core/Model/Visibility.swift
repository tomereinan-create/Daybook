import Foundation

/// Where an item is allowed to appear. `appList` is implicit for everything;
/// an item with an empty set still shows inside the app.
nonisolated struct SurfaceSet: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let liveActivity = SurfaceSet(rawValue: 1 << 0)
    static let homeWidget   = SurfaceSet(rawValue: 1 << 1)

    static let all: SurfaceSet = [.liveActivity, .homeWidget]
    static let appOnly: SurfaceSet = []
}

/// A single surface the engine can be asked to plan for.
nonisolated enum Surface: String, Sendable, Hashable, CaseIterable {
    case liveActivity
    case homeWidget
    case app

    var member: SurfaceSet {
        switch self {
        case .liveActivity: .liveActivity
        case .homeWidget: .homeWidget
        case .app: []
        }
    }
}

nonisolated struct Visibility: Codable, Sendable, Hashable {
    /// How long before the trigger the item starts appearing, in seconds.
    var leadTime: TimeInterval
    var surfaces: SurfaceSet

    static let standard = Visibility(leadTime: 2 * 3600, surfaces: .all)
    static let hidden = Visibility(leadTime: 0, surfaces: .appOnly)
}
