import MapKit
import SwiftUI

/// Shows captured start options and delegates the selection to the navigation owner.
struct RouteStartReviewView: View {
    let suggestedCoordinates: [CLLocationCoordinate2D]
    let alternateCoordinates: [CLLocationCoordinate2D]
    let onUseSuggestedStart: () -> Void
    let onUseOtherStart: () -> Void
    let onCancel: () -> Void

    /// Displays captured start alternatives and forwards the user’s choice to the parent.
    var body: some View {
        NavigationStack {
            let hasAlternateStart = alternateCoordinates.count >= 2
            Map(initialPosition: .automatic) {
                UserAnnotation()

                if suggestedCoordinates.count >= 2 {
                    MapPolyline(coordinates: suggestedCoordinates)
                        .stroke(.blue, lineWidth: 6)

                    if let start = suggestedCoordinates.first {
                        Marker("Suggested start", coordinate: start)
                            .tint(.blue)
                    }
                }

                if hasAlternateStart {
                    MapPolyline(coordinates: alternateCoordinates)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))

                    if let start = alternateCoordinates.first {
                        Marker("Other start", coordinate: start)
                            .tint(.orange)
                    }
                }
            }
            .navigationTitle("Choose your starting path")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text("Choose the route that starts on your walkway.")
                        .font(.subheadline)

                    Button("Use Suggested Start") {
                        onUseSuggestedStart()
                    }
                    .buttonStyle(.borderedProminent)

                    if hasAlternateStart {
                        Button("Use Other Start") {
                            onUseOtherStart()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}
