//
//  LocalRoutePoint.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 11/4/26.
//

import MapKit

struct LocalRoutePoint {
    let eastMeters: Double
    let northMeters: Double
    
    var arOffset: SIMD3<Float> {
        // groups offests and height change
        SIMD3<Float>(Float(eastMeters), 0, -Float(northMeters))
    }
    
    // How far east or west, and how dar north or south the point is from the origin
    static func from(coordinate: CLLocationCoordinate2D, relativeTo origin: CLLocationCoordinate2D) -> LocalRoutePoint {
        let start = MKMapPoint(origin)
        let point = MKMapPoint(coordinate)
        // Turns origin latitude into into aproximate ground meters
        let metersPerPoint = MKMetersPerMapPointAtLatitude(origin.latitude)
        
        // returns the east meters and north meters
        return LocalRoutePoint(eastMeters: (point.x - start.x) * metersPerPoint, northMeters: (start.y - point.y) * metersPerPoint)
    }
}
