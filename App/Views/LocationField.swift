import CoreLocation
import MapKit
import SwiftUI

/// Choosing a place, a radius, and whether arriving or leaving is the trigger.
///
/// Tap the map to move the pin. That is the whole interaction — a place
/// reminder is not worth a search field and a list of results until someone
/// asks for one.
struct LocationField: View {
    @Binding var settings: ItemSettings
    @State private var camera: MapCameraPosition = .automatic

    private var location: LocationTrigger {
        settings.trigger.location ?? .unset
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var hasPlace: Bool {
        settings.trigger.location != nil
    }

    var body: some View {
        TextField("field.placeName", text: nameBinding)

        MapReader { proxy in
            Map(position: $camera) {
                if hasPlace {
                    Marker(location.name, coordinate: coordinate)
                        .tint(.accentColor)
                    MapCircle(center: coordinate, radius: location.radius)
                        .foregroundStyle(Color.accentColor.opacity(0.18))
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
                UserAnnotation()
            }
            .frame(height: 180)
            .clipShape(.rect(cornerRadius: 12))
            .onTapGesture { point in
                guard let tapped = proxy.convert(point, from: .local) else { return }
                move(to: tapped)
            }
            .accessibilityLabel(Text("field.placeMap"))
            .accessibilityHint(Text("field.placeMap.hint"))
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

        if !hasPlace {
            Text("field.placeMap.empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Picker("field.placeEdge", selection: edgeBinding) {
            Text("edge.arrive").tag(LocationEdge.arrive)
            Text("edge.leave").tag(LocationEdge.leave)
        }

        Picker("field.placeRadius", selection: radiusBinding) {
            ForEach([100.0, 200.0, 500.0, 1000.0], id: \.self) { metres in
                Text(Formatting.distance(metres)).tag(metres)
            }
        }
    }

    // MARK: - Bindings

    private func move(to coordinate: CLLocationCoordinate2D) {
        var updated = location
        updated.latitude = coordinate.latitude
        updated.longitude = coordinate.longitude
        settings.trigger.kind = .location
        settings.trigger.location = updated
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { location.name },
            set: { newValue in
                var updated = location
                updated.name = newValue
                settings.trigger.location = updated
            }
        )
    }

    private var edgeBinding: Binding<LocationEdge> {
        Binding(
            get: { location.edge },
            set: { newValue in
                var updated = location
                updated.edge = newValue
                settings.trigger.location = updated
            }
        )
    }

    private var radiusBinding: Binding<Double> {
        Binding(
            get: { location.radius },
            set: { newValue in
                var updated = location
                updated.radius = newValue
                settings.trigger.location = updated
            }
        )
    }
}

nonisolated extension LocationTrigger {
    /// A place with no coordinate yet. The editor shows the map empty until the
    /// user taps it, rather than dropping a pin somewhere arbitrary.
    static let unset = LocationTrigger(
        name: "",
        latitude: 0,
        longitude: 0,
        radius: 200,
        edge: .arrive
    )
}

nonisolated extension Formatting {
    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
