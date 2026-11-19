import CoreLocation
import MapKit

/// The closest geographic point on a segment and its distance from the GPS fix.
struct WalkingStartMatch {
    let edge: WalkingEdge
    let coordinate: CLLocationCoordinate2D
    let fractionAlongEdge: Double
    let distanceFromUser: Double
}

/// The closest geographic point on a segment and its distance from the GPS fix.
/// Projects geographic locations onto mapped walkway segments.
struct WalkingStartMatcher {

    /// Clamps the projection to the segment endpoints so the start stays on the walkway.
    func match(location: CLLocation, to edge: WalkingEdge, coordinates: [String: CLLocationCoordinate2D])
        -> WalkingStartMatch?
    {
        guard let fromCoordinate = coordinates[edge.fromNodeID],
            let toCoordinate = coordinates[edge.toNodeID]
        else {
            return nil
        }

        let startPoint = MKMapPoint(fromCoordinate)
        let endPoint = MKMapPoint(toCoordinate)
        let userPoint = MKMapPoint(location.coordinate)

        let segmentX = endPoint.x - startPoint.x
        let segmentY = endPoint.y - startPoint.y

        let userX = userPoint.x - startPoint.x
        let userY = userPoint.y - startPoint.y

        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY

        guard segmentLengthSquared > 0 else {
            return nil
        }

        // The dot product locates the projection along the segment; clamping keeps it on the path.
        let fraction = (userX * segmentX + userY * segmentY) / segmentLengthSquared

        let clampedFraction = min(max(fraction, 0), 1)
        let matchedPoint = MKMapPoint(
            x: startPoint.x + clampedFraction * segmentX, y: startPoint.y + clampedFraction * segmentY)

        let matchedCoordinate = matchedPoint.coordinate
        let matchedLocation = CLLocation(
            latitude: matchedCoordinate.latitude, longitude: matchedCoordinate.longitude)

        let distanceFromUser = location.distance(from: matchedLocation)

        return WalkingStartMatch(
            edge: edge, coordinate: matchedCoordinate, fractionAlongEdge: clampedFraction,
            distanceFromUser: distanceFromUser)
    }
}
