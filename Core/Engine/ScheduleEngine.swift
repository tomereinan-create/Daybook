import Foundation

/// The single entry point every surface talks to.
///
/// Hand it the items, the per-occurrence records and a moment, and it answers
/// the four questions the app is built on: what occurrences exist, what state
/// each is in, what each surface shows, and what should be scheduled next.
/// It holds no state and touches no framework beyond Foundation.
nonisolated struct ScheduleEngine: Sendable {
    var calendar: Calendar
    var configuration: EngineConfiguration
    var quietHours: QuietHours

    init(
        calendar: Calendar = .current,
        configuration: EngineConfiguration = .default,
        quietHours: QuietHours = .default
    ) {
        self.calendar = calendar
        self.configuration = configuration
        self.quietHours = quietHours
    }

    private var generator: OccurrenceGenerator { OccurrenceGenerator(calendar: calendar) }
    private var resolver: StateResolver { StateResolver(calendar: calendar, configuration: configuration) }
    private var pacer: QuotaPacer { QuotaPacer(calendar: calendar) }
    private var planner: SurfacePlanner { SurfacePlanner(configuration: configuration) }

    // MARK: - Occurrences

    /// Every occurrence whose slot falls in `range`, resolved against `now`.
    func resolve(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        in range: Range<Date>,
        now: Date
    ) -> [ResolvedOccurrence] {
        var result: [ResolvedOccurrence] = []
        for item in items where !item.isArchived {
            for generated in generator.occurrences(for: item, in: range) {
                let quota = quotaProgress(
                    for: item,
                    generated: generated,
                    records: records,
                    now: now
                )
                result.append(
                    resolver.resolve(
                        item: item,
                        generated: generated,
                        record: records[generated.key],
                        now: now,
                        quota: quota
                    )
                )
            }
        }
        return supersedeStaleOccurrences(result, now: now)
            .sorted(by: SurfacePlanner.isOrderedBefore)
    }

    /// A recurring item is only ever outstanding once.
    ///
    /// Without this, a daily item that stays until done would stack up one
    /// unfinished copy per day and bury the widget. When a newer occurrence of
    /// the same item has arrived, the older one is closed as missed however
    /// forgiving its `onMissed` policy is. One-off items are untouched: those
    /// really do wait forever.
    private func supersedeStaleOccurrences(
        _ resolved: [ResolvedOccurrence],
        now: Date
    ) -> [ResolvedOccurrence] {
        var newestArrived: [UUID: Date] = [:]
        for occurrence in resolved where occurrence.item.settings.recurrence.frequency.repeats {
            let slot = occurrence.generated.slot
            guard slot <= now else { continue }
            newestArrived[occurrence.item.id] = max(newestArrived[occurrence.item.id] ?? .distantPast, slot)
        }
        guard !newestArrived.isEmpty else { return resolved }

        return resolved.map { occurrence in
            guard occurrence.item.settings.recurrence.frequency.repeats,
                  let newest = newestArrived[occurrence.item.id],
                  occurrence.generated.slot < newest,
                  occurrence.state.isOutstanding
            else { return occurrence }
            return occurrence.with(state: .missed)
        }
    }

    /// The range the engine scans so that nothing still outstanding is missed:
    /// back far enough to catch yesterday's unfinished tasks, forward far
    /// enough to fill the scheduling window.
    func scanRange(around now: Date) -> Range<Date> {
        let start = now.addingTimeInterval(-configuration.outstandingLookback)
        let end = now.addingTimeInterval(configuration.schedulingWindow)
        return start..<end
    }

    /// Everything currently live: occurrences from the past that are still
    /// outstanding plus everything inside the forward window.
    func live(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> [ResolvedOccurrence] {
        resolve(items: items, records: records, in: scanRange(around: now), now: now)
    }

    // MARK: - Surfaces

    func entries(
        for surface: Surface,
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> [ResolvedOccurrence] {
        planner.entries(for: surface, from: live(items: items, records: records, now: now))
    }

    /// One day, grouped the way the Today screen shows it. Occurrences from
    /// earlier days appear only when they are still outstanding.
    func dayPlan(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        on day: Date,
        now: Date
    ) -> DayPlan {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.startOfNextDay(after: day)
        let all = live(items: items, records: records, now: now)

        var sections: [DaySection: [ResolvedOccurrence]] = [:]
        for occurrence in all {
            // An item that asks for no surfaces at all is one the user has put
            // out of sight: Someday, and Waiting-for until it is chased. Those
            // belong in their lists and in the weekly review, not in today.
            guard !occurrence.item.settings.visibility.surfaces.isEmpty else { continue }

            let anchor = occurrence.effectiveTrigger ?? occurrence.generated.slot
            let landsToday = anchor >= dayStart && anchor < dayEnd
            let isCarriedOver = anchor < dayStart && occurrence.state.isOutstanding
            let isUndated = occurrence.effectiveTrigger == nil && occurrence.state.isOutstanding
            guard landsToday || isCarriedOver || isUndated else { continue }

            sections[occurrence.daySection, default: []].append(occurrence)
        }
        for key in sections.keys {
            sections[key]?.sort(by: SurfacePlanner.isOrderedBefore)
        }
        return DayPlan(day: dayStart, sections: sections)
    }

    // MARK: - Scheduling

    func notificationPlan(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> NotificationPlan {
        let resolved = live(items: items, records: records, now: now)
        let planner = NotificationPlanner(
            calendar: calendar,
            configuration: configuration,
            quietHours: quietHours
        )
        return planner.plan(for: resolved, now: now)
    }

    /// Items that need a monitored region right now, and whether the user has
    /// asked for more than CoreLocation will accept.
    func locationMonitoringPlan(
        items: [ItemSnapshot],
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> LocationMonitoringPlan {
        let active = live(items: items, records: records, now: now)
            .filter { $0.state.isOutstanding }
            .filter { $0.item.settings.trigger.kind == .location }
            .compactMap { occurrence -> MonitoredRegion? in
                guard let location = occurrence.item.settings.trigger.location else { return nil }
                return MonitoredRegion(key: occurrence.key, title: occurrence.displayTitle, trigger: location)
            }
        let limit = configuration.locationRegionLimit
        return LocationMonitoringPlan(
            monitored: Array(active.prefix(limit)),
            overflow: Array(active.dropFirst(limit)),
            limit: limit
        )
    }

    // MARK: - Quota

    private func quotaProgress(
        for item: ItemSnapshot,
        generated: GeneratedOccurrence,
        records: [OccurrenceKey: OccurrenceStateRecord],
        now: Date
    ) -> QuotaProgress? {
        guard case .quota(let count, _) = item.settings.recurrence.frequency,
              let period = generated.quotaPeriod else { return nil }
        // One occurrence stands for the whole period, so its record carries a
        // tally rather than a single completion date.
        let completions = records[generated.key]?.completionCount ?? 0
        return pacer.progress(
            target: count,
            completionsInPeriod: completions,
            period: period,
            now: now
        )
    }
}

nonisolated struct MonitoredRegion: Sendable, Hashable, Identifiable {
    let key: OccurrenceKey
    let title: String
    let trigger: LocationTrigger

    var id: OccurrenceKey { key }
}

nonisolated struct LocationMonitoringPlan: Sendable {
    let monitored: [MonitoredRegion]
    /// Regions the platform cap left out. The app surfaces these as a warning
    /// rather than failing quietly.
    let overflow: [MonitoredRegion]
    let limit: Int

    var exceedsLimit: Bool { !overflow.isEmpty }
}
