import Foundation

/// Decides what each surface shows, and in what order.
///
/// Ordering, highest first: mandatory before normal, then how urgent the state
/// is, then the soonest trigger, then title so the result is stable.
nonisolated struct SurfacePlanner: Sendable {
    var configuration: EngineConfiguration

    init(configuration: EngineConfiguration = .default) {
        self.configuration = configuration
    }

    func entries(for surface: Surface, from resolved: [ResolvedOccurrence]) -> [ResolvedOccurrence] {
        let eligible = resolved.filter { shows($0, on: surface) }
        let ordered = eligible.sorted(by: Self.isOrderedBefore)
        let limit = limit(for: surface)
        return limit.map { Array(ordered.prefix($0)) } ?? ordered
    }

    func shows(_ occurrence: ResolvedOccurrence, on surface: Surface) -> Bool {
        switch surface {
        case .app:
            return true
        case .liveActivity, .homeWidget:
            guard occurrence.state.appearsOnLiveSurfaces else { return false }
            return occurrence.item.settings.visibility.surfaces.contains(surface.member)
        }
    }

    private func limit(for surface: Surface) -> Int? {
        switch surface {
        case .liveActivity: configuration.liveActivityEntryCount
        case .homeWidget: configuration.homeWidgetEntryCount
        case .app: nil
        }
    }

    static func isOrderedBefore(_ a: ResolvedOccurrence, _ b: ResolvedOccurrence) -> Bool {
        let aMandatory = a.item.settings.priority == .mandatory
        let bMandatory = b.item.settings.priority == .mandatory
        if aMandatory != bMandatory { return aMandatory }

        if a.state.sortRank != b.state.sortRank {
            return a.state.sortRank < b.state.sortRank
        }

        switch (a.effectiveTrigger, b.effectiveTrigger) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs
        case (nil, .some):
            // Dated items come before undated ones at the same urgency.
            return false
        case (.some, nil):
            return true
        default:
            break
        }

        if a.title != b.title { return a.title < b.title }
        return a.key.itemID.uuidString < b.key.itemID.uuidString
    }
}

/// Everything the Today screen needs for one day, already grouped.
nonisolated struct DayPlan: Sendable {
    let day: Date
    let sections: [DaySection: [ResolvedOccurrence]]

    subscript(section: DaySection) -> [ResolvedOccurrence] {
        sections[section] ?? []
    }

    var isEmpty: Bool { sections.values.allSatisfy(\.isEmpty) }

    var completionCount: Int { self[.done].count }

    var outstandingCount: Int {
        self[.now].count + self[.upcoming].count + self[.undated].count
    }
}
