import MapKit
import SwiftUI

/// Presents the active route without owning progress, rerouting, or arrival decisions.
struct ARNavigationMapView<Summary: View>: View {
    let destinationName: String
    let remainingCoordinates: [CLLocationCoordinate2D]
    let endpoint: CLLocationCoordinate2D?
    let locationManager: LocationManager
    let summary: Summary
    let onBackToAR: () -> Void
    @State private var routeMapHeading: Double = 0

    /// Displays the remaining active route with heading and the parent’s navigation summary.
    var body: some View {
        NavigationStack {

            Map(initialPosition: .automatic, bounds: MapCameraBounds(minimumDistance: 150)) {
                UserAnnotation {
                    ZStack {
                        if let heading = locationManager.headingDegrees {
                            HeadingCone(halfAngle: locationManager.headingHalfAngle)
                                .fill(.yellow.opacity(0.3))
                                .rotationEffect(.degrees(heading - routeMapHeading))
                        }
                        Circle()
                            .fill(.yellow)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().stroke(.white, lineWidth: 2)
                            }
                    }
                    .frame(width: 100, height: 100)
                }

                if remainingCoordinates.count >= 2 {
                    MapPolyline(coordinates: remainingCoordinates)
                        .stroke(.yellow, lineWidth: 5)
                }

                if let endpoint = endpoint {
                    Marker(destinationName, coordinate: endpoint)
                }
            }
            .safeAreaInset(edge: .bottom) {
                summary
                    .padding()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                routeMapHeading = context.camera.heading
            }
            .navigationTitle(destinationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to AR") {
                        onBackToAR()
                    }
                }
            }
        }
    }
}
