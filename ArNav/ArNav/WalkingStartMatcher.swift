//
//  WalkingStartMatcher.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 10/27/26.
//

import CoreLocation
import MapKit

struct WalkingStartMatch {
    let edge: WalkingEdge
    let coordinate: CLLocationCoordinate2D
    let fractionAlongEdge: Double
    let distanceFromUser: Double
}

struct WalkingStartMatcher {
    
    // Matches the user to a starting point
    func match(location: CLLocation, to edge: WalkingEdge, coordinates: [String: CLLocationCoordinate2D]) -> WalkingStartMatch? {
        guard let fromCoordinate = coordinates[edge.fromNodeID],
              let toCoordinate = coordinates[edge.toNodeID] else {
            return nil
        }
        
        // Converts latitude and longitude into x and y position on MapKit's
        let startPoint = MKMapPoint(fromCoordinate)
        let endPoint = MKMapPoint(toCoordinate)
        let userPoint = MKMapPoint(location.coordinate)
        
        // Segment offset From the starting point
        let segmentX = endPoint.x - startPoint.x
        let segmentY = endPoint.y - startPoint.y
        
        // User offset from the starting point
        let userX = userPoint.x - startPoint.x
        let userY = userPoint.y - startPoint.y
        
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        
        guard segmentLengthSquared > 0 else {
            return nil
        }
        
        // Stores the fraction of the closest point on the segement.
        let fraction = (userX * segmentX + userY * segmentY) / segmentLengthSquared
        
        // Prevents the point from going beyond either endpoint
        let clampedFraction = min(max(fraction, 0), 1)
        //finding the point along the segmoent
        let matchedPoint = MKMapPoint(x: startPoint.x + clampedFraction * segmentX, y: startPoint.y + clampedFraction * segmentY)
        
        // turns points into lat and long
        let matchedCoordinate = matchedPoint.coordinate
        // Stores the mathed Coordinate a CLLocation point
        let matchedLocation = CLLocation(latitude: matchedCoordinate.latitude, longitude: matchedCoordinate.longitude)
        
        // Finds the the distance from the user
        let distanceFromUser = location.distance(from: matchedLocation)
        
        return WalkingStartMatch(edge: edge, coordinate: matchedCoordinate, fractionAlongEdge: clampedFraction, distanceFromUser: distanceFromUser)
    }
}
