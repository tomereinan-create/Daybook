import CoreLocation
import Foundation

enum LocationAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    /// Granted, but only while the app is open — which is not enough for a
    /// place reminder to fire when it matters.
    case whenInUse
    case always

    var canMonitor: Bool { self == .always }
}

/// Region identifiers have to survive a round trip through CoreLocation, which
/// wants a plain alphanumeric string.
nonisolated extension MonitoredRegion {
    var monitorIdentifier: String {
        let id = key.itemID.uuidString.replacingOccurrences(of: "-", with: "")
        return "\(id)x\(Int(key.slot.timeIntervalSince1970))x\(trigger.edge.rawValue)"
    }

    static func decode(_ identifier: String) -> (key: OccurrenceKey, edge: LocationEdge)? {
        let parts = identifier.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 32,
              let seconds = TimeInterval(parts[1]),
              let edge = LocationEdge(rawValue: String(parts[2]))
        else { return nil }

        var hex = String(parts[0])
        for offset in [8, 13, 18, 23] {
            hex.insert("-", at: hex.index(hex.startIndex, offsetBy: offset))
        }
        guard let itemID = UUID(uuidString: hex) else { return nil }
        return (OccurrenceKey(itemID: itemID, slot: Date(timeIntervalSince1970: seconds)), edge)
    }
}

/// Watches the places the user's items care about.
///
/// CoreLocation stops monitoring past about twenty regions, and the engine
/// already reports which ones did not fit. This keeps the monitored set in
/// line with that plan and hands the overflow back so the app can say so
/// rather than quietly not working.
@MainActor
final class LocationMonitorController: NSObject {
    static let shared = LocationMonitorController()

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    private var observation: Task<Void, Never>?

    /// Called when a region the user cares about is entered or left.
    var onTrigger: (@MainActor (OccurrenceKey) -> Void)?
    /// Called when permission changes, because granting Always is the moment
    /// monitoring becomes possible and the app has to try again.
    var onAuthorizationChange: (@MainActor () -> Void)?

    private(set) var overflow: [MonitoredRegion] = []

    private override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Place reminders need Always. Ask for When In Use first, because iOS will
    /// not grant Always from a cold start anyway.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Brings the monitored regions into line with the plan. Idempotent, like
    /// the notification reconciler, so it is safe on every refresh.
    func sync(_ plan: LocationMonitoringPlan) async {
        overflow = plan.overflow

        guard authorization.canMonitor else {
            await stop()
            return
        }
        guard !plan.monitored.isEmpty else {
            await stop()
            return
        }

        let monitor = await currentMonitor()
        let wanted = Dictionary(
            plan.monitored.map { ($0.monitorIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existing = Set(await monitor.identifiers)

        for stale in existing.subtracting(wanted.keys) {
            await monitor.remove(stale)
        }
        for (identifier, region) in wanted where !existing.contains(identifier) {
            await monitor.add(
                CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(
                        latitude: region.trigger.latitude,
                        longitude: region.trigger.longitude
                    ),
                    radius: region.trigger.radius
                ),
                identifier: identifier
            )
        }
        startObserving(monitor)
    }

    func stop() async {
        observation?.cancel()
        observation = nil
        guard let monitor else { return }
        for identifier in await monitor.identifiers {
            await monitor.remove(identifier)
        }
    }

    // MARK: - Plumbing

    private func currentMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        return created
    }

    private static let monitorName = "DaybookPlaces"

    private func startObserving(_ monitor: CLMonitor) {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard !Task.isCancelled else { return }
                    await self?.handle(event)
                }
            } catch {
                // The stream ends when monitoring stops. Nothing to recover.
            }
        }
    }

    private func handle(_ event: CLMonitor.Event) {
        guard let decoded = MonitoredRegion.decode(event.identifier) else { return }
        // Arriving satisfies the condition; leaving stops satisfying it. An
        // item asks for one edge, so the other one is not its business.
        let fired = switch decoded.edge {
        case .arrive: event.state == .satisfied
        case .leave: event.state == .unsatisfied
        }
        guard fired else { return }
        onTrigger?(decoded.key)
    }
}

extension LocationMonitorController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.onAuthorizationChange?()
        }
    }
}
