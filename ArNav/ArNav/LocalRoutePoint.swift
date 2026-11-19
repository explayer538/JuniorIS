import MapKit

/// A geographic point expressed in local east/north meters.
struct LocalRoutePoint {
    let eastMeters: Double
    let northMeters: Double

    /// Converts north-positive geographic offsets to RealityKit’s negative-Z north axis.
    var arOffset: SIMD3<Float> {
        SIMD3<Float>(Float(eastMeters), 0, -Float(northMeters))
    }

    /// Uses the origin latitude to convert MapKit coordinates into approximate ground meters.
    static func from(coordinate: CLLocationCoordinate2D, relativeTo origin: CLLocationCoordinate2D)
        -> LocalRoutePoint
    {
        let start = MKMapPoint(origin)
        let point = MKMapPoint(coordinate)
        // MapKit uses projected units, whose ground scale depends on latitude.
        let metersPerPoint = MKMetersPerMapPointAtLatitude(origin.latitude)

        return LocalRoutePoint(
            eastMeters: (point.x - start.x) * metersPerPoint,
            northMeters: (start.y - point.y) * metersPerPoint)
    }
}
