//
//  ARCameraView.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 11/3/26.
//

import SwiftUI
// Provides AR view
import RealityKit
// Tracks phone's Movement and detects real-world Surfaces
import ARKit
import CoreLocation


// UIView representable helps make UIView into SwiftUI.
struct ARCameraView: UIViewRepresentable {
    
    @Binding var trackingMessage: String
    
    let routeCoordinates: [CLLocationCoordinate2D]
    
    let surfaceCheckCount: Int
    @Binding var surfaceMessage: String
    
    @Binding var detectedSurfacePoint: SIMD3<Float>?
    
    let routeStartOffset: LocalRoutePoint?
    
    
    // stores an array local points used for Drawing AR route
    private var localRoutePoints: [LocalRoutePoint] {
        // Set the start
        guard let origin = routeCoordinates.first else {
            return []
        }
        // returning a mapping of each coordinate local point from orign to coordinate
        return routeCoordinates.map { coordinate in
            LocalRoutePoint.from(coordinate: coordinate, relativeTo: origin)
        }
    }
    
    // returns the nearby offsets within the range given
    private func nearbyRouteOffset(limitMeters: Float) -> [SIMD3<Float>] {
        guard limitMeters > 0, let first = localRoutePoints.first else {
            return []
        }
        
        var points = [first.arOffset]
        var previous = first.arOffset
        var remaining = limitMeters
        
        for routePoint in localRoutePoints.dropFirst() {
            let next = routePoint.arOffset
            let step = next - previous
            let length = hypot(step.x, step.z)
            
            guard length > 0 else {continue}
            
            if length >= remaining {
                let fraction = remaining / length
                points.append(previous + step * fraction)
                break
            }
            
            points.append(next)
            remaining -= length
            previous = next
        }
        return points
    }
    
    // Creates ARView
    func makeUIView(context: Context) -> ARView{
        // Makes a view with no assigned size in ar camera mode, which does not automatically connifgure
       let arView =  ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        // Setting up our coordinator to receive updates
        arView.session.delegate = context.coordinator
        
        // Checks whether the device allows this tracking mode
        guard ARWorldTrackingConfiguration.isSupported else {
            return arView
        }
        
        // Object that tracks the phone's Position and orientation
        let configuration = ARWorldTrackingConfiguration()
        // setting the scene of the coordinate system
        configuration.worldAlignment = .gravityAndHeading
        // ARkit detects horizontal surfaces
        configuration.planeDetection = [.horizontal]
        
        // Starts the configures session
        arView.session.run(configuration)
        
        
        // Sends view for Display
        return arView
    }
    // allows us to change the existing view
    func updateUIView(_ uiView: UIViewType, context: Context) {
        // makes sure surface checkcount is not equal to the last
        guard surfaceCheckCount != context.coordinator.lastSurfaceCheckCount else {
            return
        }
        
        //sets the last count to the current count
        context.coordinator.lastSurfaceCheckCount = surfaceCheckCount
        
        // checks for a horizontal surface in the view
        guard let point = horizontalSurfacePoint(in: uiView) else {
            return
        }
        
        var checkMessage = "Surface dectected"
        
        // Creates and Anchor at the point found in Raycasting
        let anchor = AnchorEntity(world: point)
        
        let radius: Float = 0.04
        // Creates a yellow Sphere
        let marker = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
        
        // Increasing so Sphere touches the ground
        marker.position.y = radius
        //Positions the Sphere relative to the anchor
        anchor.addChild(marker)
        // Adds them to the scene
        uiView.scene.addAnchor(anchor)
        
        // Draw if the route offset is Available.
        if let offset = routeStartOffset?.arOffset {
            let routeStartPosition = SIMD3<Float>(offset.x, point.y, offset.z)
            
            // Anchor for the starting point
            let routeAnchor = AnchorEntity(world: routeStartPosition)
            // Creating a Blue marker for the start point and raise the y so it touches the ground
            let routeMarker = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [SimpleMaterial(color: .blue, isMetallic: false)])
            
            routeMarker.position.y = 0.05
            routeAnchor.addChild(routeMarker)
            
            // Use the first point were the distance is more than 1 cm from the start
            if let nextPoint = localRoutePoints.first(where: {point in hypot(point.eastMeters, point.northMeters) > 0.01}) {
                // Offset from start point to this point
                let offset = nextPoint.arOffset
                // Horizontal Distance
                let length = hypot(offset.x, offset.z)
                
                //Convert route Direction into compass Bearing, then converting into degrees.
                let routeDegrees = atan2(nextPoint.eastMeters, nextPoint.northMeters) * 180/Double.pi
                let routeBearing = (routeDegrees + 360).truncatingRemainder(dividingBy: 360)
                
                // compare the camera's direction with the route's
                if let frame = uiView.session.currentFrame {
                    let cameraZ = frame.camera.transform.columns.2
                    let east = -cameraZ.x
                    let north = cameraZ.z

                    if hypot(east, north) > 0.1 {
                        let degrees = atan2(Double(east), Double(north)) * 180 / Double.pi
                        let cameraBearing = (degrees + 360)
                            .truncatingRemainder(dividingBy: 360)

                        checkMessage = String(
                            format: "At placement · Route: %.0f° · Camera: %.0f° · First segment: %.1f m",
                            routeBearing, cameraBearing, Double(length)
                        )
                    } else {
                        checkMessage = "Camera was pointing nearly straight down. Retry with a gentler tilt."
                    }
                }
                
                //Draws at most 2 Meters of a segement, if it is shorter we would use the whole segment
                // Multiplying by the scale helps preserve direction
                let scale = min(1, 2/length)
                
                // Green marker with marks the end of the visible strip
                let directionMarker = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [SimpleMaterial(color: .green, isMetallic: false)])
                
                directionMarker.position = SIMD3<Float>(offset.x * scale, 0.05, offset.z * scale)
                routeAnchor.addChild(directionMarker)
                
                // Use horizontal position and length at the endpoint of the yellow strip.
                let endX = offset.x * scale
                let endZ = offset.z * scale
                let stripLength = length * scale
                
                // Make a flat yellow box: 12 cm wide, 1 cm thick, and long enough
                let strip = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.12, 0.01, stripLength)), materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
                
                // places its center halfway between blue and green, slightly above the ground.
                strip.position = SIMD3<Float>(endX / 2, 0.015, endZ / 2)
                
                
                // Turn the box from +Z toward green. Rotating around Y (the up axis)
                // keeps the strip flat. simd_quatf expresses that rotation for RealityKit
                let angle = atan2(endX, endZ)
                
                strip.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
                
                routeAnchor.addChild(strip)
            }
            
            // Add the anchor and all its children to the AR scene together.
            uiView.scene.addAnchor(routeAnchor)
        }
        
        Task { @MainActor in
            detectedSurfacePoint = point
            surfaceMessage = checkMessage
        }
    }
    // SwiftUI calls this when closing a view
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        // Stop the AR session when not on navigation screen
        uiView.session.pause()
    }
    
    // Helps receive AR Session Callbacks
    class Coordinator: NSObject, ARSessionDelegate {
        // Binding variable that gives use the same message from AR navigation
        private let trackingMessage: Binding<String>
        // Setting class tracking message variable to the one passage in the Coordinator
        init(trackingMessage: Binding<String>) {
            self.trackingMessage = trackingMessage
        }
        
        var lastSurfaceCheckCount = 0
        
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            
            let message: String  
            
            switch camera.trackingState {
            case .normal:
                message = "Camera tracking is ready."
                
            case .notAvailable:
                message = "Camera tracking is unavailable."
                
            case .limited(let reason):
                message = "AR tracking: limited - \(reason)"
            }
            
            // Scheduling Update in to UI updates
            Task { @MainActor in
                // Changin the value displayed in the AR navigation view
                self.trackingMessage.wrappedValue = message
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(trackingMessage: $trackingMessage)
    }
    
    // Checks for Horizontal surface
    private func horizontalSurfacePoint(in arView: ARView) -> SIMD3<Float>? {
        // Stores the center of the screen
        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        
        // Stores the first hit when raycasting on a detected horizontal surface
        guard let hit = arView.raycast(from: screenCenter, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            return nil
        }
        
        // Stores the postion of the imaginary plane drawn
        let position = hit.worldTransform.columns.3
        return SIMD3<Float>(position.x, position.y, position.z)
    }
}
