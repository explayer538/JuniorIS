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
    @State private var trackingMessage = "Starting AR tracking…"
    
    @State private var surfaceCheckCount = 0
    @State private var surfaceMessage = "Stand still and tilt your phone down until the walkway is in the center of the screen."
    @State private var detectedSurfacePoint: SIMD3<Float>? = nil
    
    @State private var routeProgressMeters: Float? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    private var routeStartOffset: LocalRoutePoint? {
        guard let routeStart = routeCoordinates.first else {
            return nil
        }
        
        return LocalRoutePoint.from(coordinate: routeStart, relativeTo: startLocation.coordinate)
    }
    
    var body: some View {
        ZStack {
            // Displays the AR Camera
            ARCameraView(trackingMessage: $trackingMessage, routeCoordinates: routeCoordinates, surfaceCheckCount: surfaceCheckCount, surfaceMessage: $surfaceMessage, detectedSurfacePoint: $detectedSurfacePoint, routeProgressMeters: $routeProgressMeters, routeStartOffset: routeStartOffset)
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
                // Checks for horizontal surface
                Button("Check surface") {
                    surfaceCheckCount += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(detectedSurfacePoint != nil)
                
                Text(surfaceMessage)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                
            }
            .padding()
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
