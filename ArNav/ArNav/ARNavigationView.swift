//
//  ARNavigationView.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 11/3/26.
//

import SwiftUI
import CoreLocation

struct ARNavigationView: View {
    let destinationName: String
    let routeCoordinates: [CLLocationCoordinate2D]
    let startLocation: CLLocation
    let locationManger: LocationManager
    @State private var trackingMessage = "Starting AR tracking…"
    
    @State private var surfaceCheckCount = 0
    @State private var alignmentRequestCount = 0
    @State private var surfaceMessage = "Stand still and tilt your phone down until the walkway is in the center of the screen."
    @State private var detectedSurfacePoint: SIMD3<Float>? = nil
    
    @State private var routeProgressMeters: Float? = nil
    @State private var distanceFromRouteMeters: Float? = nil
    @State private var lastGPSFixTimestamp: Date?
    @State private var consecutiveOffRouteGPSFixes = 0
    
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
    
    var body: some View {
        ZStack {
            // Displays the AR Camera
            ARCameraView(trackingMessage: $trackingMessage, routeCoordinates: routeCoordinates, surfaceCheckCount: surfaceCheckCount, surfaceMessage: $surfaceMessage, detectedSurfacePoint: $detectedSurfacePoint, routeProgressMeters: $routeProgressMeters, distanceFromRouteMeters: $distanceFromRouteMeters, routeStartOffset: routeStartOffset, alignmentRequestCount: alignmentRequestCount)
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
                            // Navigation amp
                        }
                        .disabled(true)
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
        .onChange(of: locationManger.currentLocation?.horizontalAccuracy, initial: true) {
            updateGPSDeviationEvidence()
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
