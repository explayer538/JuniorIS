//
//  ARNavigationView.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 11/3/26.
//

import SwiftUI
import CoreLocation
import MapKit

struct ARNavigationView: View {
    let destinationName: String
    let routeCoordinates: [CLLocationCoordinate2D]
    let startLocation: CLLocation
    let locationManger: LocationManager
    let rerouteMessage: String?
    let onReroute: () -> Bool
    @State private var trackingMessage = "Starting AR tracking…"
    @State private var isShowingRouteMap = false
    @State private var routeMapHeading: Double = 0
    @State private var lastUsableMapProgress: Double?
    
    @State private var surfaceCheckCount = 0
    @State private var alignmentRequestCount = 0
    @State private var surfaceMessage = "Stand still and tilt your phone down until the walkway is in the center of the screen."
    @State private var detectedSurfacePoint: SIMD3<Float>? = nil
    
    @State private var routeProgressMeters: Float? = nil
    @State private var distanceFromRouteMeters: Float? = nil
    @State private var lastGPSFixTimestamp: Date?
    @State private var consecutiveOffRouteGPSFixes = 0
    @State private var lastRerouteAttempt: Date?
    
    @Environment(\.dismiss) private var dismiss
    
    private var routeStartOffset: LocalRoutePoint? {
        guard let routeStart = routeCoordinates.first else {
            return nil
        }
        
        return LocalRoutePoint.from(coordinate: routeStart, relativeTo: startLocation.coordinate)
    }
    
    private var currentGPSRoutePoint: LocalRoutePoint? {
        guard let location = locationManger.currentLocation,
              let routeOrigin = routeCoordinates.first else {
            return nil
        }
        let age = Date().timeIntervalSince(location.timestamp)
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 10, age >= -5, age <= 15 else {
                return nil
            }

        return LocalRoutePoint.from(coordinate: location.coordinate, relativeTo: routeOrigin)
    }
    
    private var gpsRouteMatch: (progress: Double, distance: Double)? {
        guard let gpsPoint = currentGPSRoutePoint,
              let origin = routeCoordinates.first, routeCoordinates.count >= 2 else {
            return nil
        }
        let points = routeCoordinates.map { coordinate in
            LocalRoutePoint.from(coordinate: coordinate, relativeTo: origin)
        }
        
        var distanceBeforeSegment = 0.0
        var closestDistance = Double.infinity
        var bestProgress: Double? = nil
        
        for (start, end) in zip(points, points.dropFirst()) {
            let east = end.eastMeters - start.eastMeters
            let north = end.northMeters - start.northMeters
            let lengthSquared = east * east + north * north

            guard lengthSquared > 0 else {
                continue
            }

            let length = sqrt(lengthSquared)

            let userEast = gpsPoint.eastMeters - start.eastMeters
            let userNorth = gpsPoint.northMeters - start.northMeters

            let fraction = min(1, max(0, (userEast * east + userNorth * north) / lengthSquared))

            let closestEast = start.eastMeters + east * fraction
            let closestNorth = start.northMeters + north * fraction

            let distance = hypot(gpsPoint.eastMeters - closestEast, gpsPoint.northMeters - closestNorth)

            if distance < closestDistance {
                closestDistance = distance
                bestProgress = distanceBeforeSegment + length * fraction
            }

            distanceBeforeSegment += length
        }
        
        guard let bestProgress else {
            return nil
        }
        
        return (progress: bestProgress, distance: closestDistance)
    }
    
    private var gpsSupportsARRealignment: Bool {
        guard let location = locationManger.currentLocation,
              let match = gpsRouteMatch else {
            return false
        }
        
        let age = Date().timeIntervalSince(location.timestamp)
        
        guard age >= -5, age <= 5, location.horizontalAccuracy <= 5 else {
            return false
        }
        
        return match.distance <= 3
    }
    
    private var hasConfirmedRouteDeviation: Bool {
        guard consecutiveOffRouteGPSFixes >= 3,
              let location = locationManger.currentLocation,
              let lastGPSFixTimestamp,
              location.timestamp == lastGPSFixTimestamp else {
            return false
        }
        
        let age = Date().timeIntervalSince(location.timestamp)
        return age >= -5 && age <= 5
    }
    
    private var remainingMapRouteCoordinates: [CLLocationCoordinate2D] {
        guard let origin = routeCoordinates.first, let progress = lastUsableMapProgress else {
            //Show the full route when there is not usable GPS match.
            return routeCoordinates
        }
        
        var distanceBeforeSegment = 0.0
        
        for index in routeCoordinates.indices.dropLast() {
            let start = routeCoordinates[index]
            let end = routeCoordinates[index + 1]
            
            //Meter converstion from GPS progress calculation.
            let localStart = LocalRoutePoint.from(coordinate: start, relativeTo: origin)
            let localEnd = LocalRoutePoint.from(coordinate: end, relativeTo: origin)
            let length = hypot(localEnd.eastMeters - localStart.eastMeters, localEnd.northMeters - localStart.northMeters)
            
            guard length > 0 else { continue }
            let segmentEnd = distanceBeforeSegment + length
            if progress < segmentEnd {
                
                let fraction = (progress - distanceBeforeSegment) / length
                let matchedCoordinate = CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
                // Keep every point after the matched
                return [matchedCoordinate] + Array(routeCoordinates.dropFirst(index + 1))
            }
            
            distanceBeforeSegment = segmentEnd
        }
        // At End there is no remainf line
        return []
    }
    
    private func updateGPSDeviationEvidence() {
        guard let location = locationManger.currentLocation,
              let match = gpsRouteMatch else {
            lastGPSFixTimestamp = nil
            consecutiveOffRouteGPSFixes = 0
            return
        }
        
        let timestamp = location.timestamp
        
        if let previousTimestamp = lastGPSFixTimestamp {
            guard timestamp > previousTimestamp else { return }
            
            if timestamp.timeIntervalSince(previousTimestamp) > 5 {
                consecutiveOffRouteGPSFixes = 0
            }
        }
        
        lastGPSFixTimestamp = timestamp
        
        let offRouteThreshold = location.horizontalAccuracy + 5.0
        
        if match.distance > offRouteThreshold {
            consecutiveOffRouteGPSFixes += 1
        } else {
            consecutiveOffRouteGPSFixes = 0
        }
    }
    
    // Rerouting the user from AR navi
    private func rerouteIfNeeded() {
        guard hasConfirmedRouteDeviation else { return }
        
        let now = Date()
        
        // Wait at at least 10 seconds between atempts
        if let lastRerouteAttempt, now.timeIntervalSince(lastRerouteAttempt) < 10 {
            return
        }
        
        lastRerouteAttempt = now
        
        if !onReroute() {
            surfaceMessage = "Couldn't find a new route from your current location"
        }
        
    }
    
    var body: some View {
        ZStack {
            // Displays the AR Camera
            ARCameraView(trackingMessage: $trackingMessage, routeCoordinates: routeCoordinates, surfaceCheckCount: surfaceCheckCount, surfaceMessage: $surfaceMessage, detectedSurfacePoint: $detectedSurfacePoint, routeProgressMeters: $routeProgressMeters, distanceFromRouteMeters: $distanceFromRouteMeters, routeStartOffset: routeStartOffset, alignmentRequestCount: alignmentRequestCount, gpsSupportsRealignment: {gpsSupportsARRealignment})
                .ignoresSafeArea()
            
            VStack {
                HStack{
                    // Destination name
                    Text(destinationName)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    //Tracking message
                    Text(trackingMessage)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    
                    
                    //Creates a system Menu
                    Menu {
                        // Option to view Map
                        Button("View Map") {
                            isShowingRouteMap = true
                        }
                        // Option to exit navigation
                        Button("Exit Navigation", role: .destructive) {
                            dismiss()
                        }
                    } label: {
                        // menu image label
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            
                    }
                    .accessibilityLabel("Navigation options")
                    
                    
                }
                if hasConfirmedRouteDeviation {
                    Text("GPS indicates you’ve left the route.")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                if let rerouteMessage {
                    Text(rerouteMessage)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                if let progress = routeProgressMeters {
                    Text("Route progress: \(progress, specifier: "%.1f") m")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                } else {
                    Text("Waiting for route progress…")
                            .foregroundStyle(.white)
                }
                #if DEBUG
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(spacing: 4) {
                        if let fix = locationManger.currentLocation {
                            let age = timeline.date.timeIntervalSince(fix.timestamp)
                            
                            Text("GPS accuracy: \(fix.horizontalAccuracy, specifier: "%.1f") m")
                            Text("GPS fix age: \(age, specifier: "%.1f") s")
                        } else {
                            Text("No GPS fix received")
                        }
                        Text("Consecutive off-route fixes: \(consecutiveOffRouteGPSFixes)")
                    
                    }
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                
                
                if let distance = distanceFromRouteMeters {
                    Text("Distance from AR route: \(distance, specifier: "%.1f") m")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if let gpsMatch = gpsRouteMatch {
                    Text("GPS route progress: \(gpsMatch.progress, specifier: "%.1f") m")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    Text("Distance from mapped route: \(gpsMatch.distance, specifier: "%.1f") m")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                } else {
                    Text("Waiting for a usable GPS location…")
                        .foregroundStyle(.white)
                }
                // Checks for horizontal surface
                Button("Check surface") {
                    surfaceCheckCount += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(detectedSurfacePoint != nil)
                #endif
                
                Button("Align Route") {
                    alignmentRequestCount += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(detectedSurfacePoint == nil || routeProgressMeters == nil)
                
                Text(surfaceMessage)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                
            }
            .padding()
        }
        // Shows Map when users Clicks on View Map
        .sheet(isPresented: $isShowingRouteMap) {
            NavigationStack {
                
                let remainingCoordinates = remainingMapRouteCoordinates
                Map(initialPosition: .automatic) {
                    UserAnnotation {
                        ZStack {
                            if let heading = locationManger.headingDegrees {
                                HeadingCone(halfAngle: locationManger.headingHalfAngle)
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
                    
                    if let endpoint = routeCoordinates.last {
                        Marker(destinationName, coordinate: endpoint)
                    }
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    routeMapHeading = context.camera.heading
                }
                .navigationTitle(destinationName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back to AR") {
                            isShowingRouteMap = false
                        }
                    }
                }
            }
        }
        .onChange(of: locationManger.currentLocation?.timestamp, initial: true) {
            if let match = gpsRouteMatch {
                lastUsableMapProgress = match.progress
            }
            updateGPSDeviationEvidence()
            rerouteIfNeeded()
        }
        .task(id: detectedSurfacePoint == nil) {
            // Prevents another loop from starting When surface found
            guard detectedSurfacePoint == nil else {return}
            
            // While SwiftUI has not cancelled the task
            while !Task.isCancelled {
                do {
                    // Pauses the task for half a second to help camera and menu responsive
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                // try raycasting
                surfaceCheckCount += 1
            }
        }
    }
}
