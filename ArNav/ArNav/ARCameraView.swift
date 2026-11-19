import ARKit
import CoreLocation
import RealityKit
import SwiftUI

/// Bridges the AR session and route coordinator into the SwiftUI navigation screen.
struct ARCameraView: UIViewRepresentable {

    @Binding var trackingMessage: String

    let routeCoordinates: [CLLocationCoordinate2D]

    let surfaceCheckCount: Int

    @Binding var surfaceMessage: String
    @Binding var detectedSurfacePoint: SIMD3<Float>?
    @Binding var routeProgressMeters: Float?
    @Binding var distanceFromRouteMeters: Float?

    let routeStartOffset: LocalRoutePoint?
    let alignmentRequestCount: Int
    let gpsSupportsRealignment: () -> Bool

    /// Expresses every route coordinate relative to the route origin for RealityKit drawing.
    private var localRoutePoints: [LocalRoutePoint] {
        guard let origin = routeCoordinates.first else {
            return []
        }
        return routeCoordinates.map { coordinate in
            LocalRoutePoint.from(coordinate: coordinate, relativeTo: origin)
        }
    }

    /// Starts heading-aligned world tracking with horizontal surface detection.
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session.delegate = context.coordinator

        guard ARWorldTrackingConfiguration.isSupported else {
            return arView
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal]

        arView.session.run(configuration)

        return arView
    }

    /// Handles explicit alignment requests before attempting one-time surface placement.
    func updateUIView(_ uiView: UIViewType, context: Context) {
        context.coordinator.gpsSupportsRealignment = gpsSupportsRealignment
        if alignmentRequestCount != context.coordinator.lastAlignmentRequestCount {
            context.coordinator.lastAlignmentRequestCount = alignmentRequestCount

            // Read the current frame when the manual request is handled, rather than capturing an earlier frame.
            Task { @MainActor in
                guard let frame = uiView.session.currentFrame else {
                    surfaceMessage = "Wait for camera tracking to be ready."
                    return
                }
                let result = context.coordinator.alignRoute(in: frame)
                surfaceMessage = result.message
            }
            return
        }
        // Place once; later surface checks must not overwrite a calibrated or recovering route.
        guard context.coordinator.routeAnchor == nil else {
            return
        }
        guard surfaceCheckCount != context.coordinator.lastSurfaceCheckCount else {
            return
        }

        context.coordinator.lastSurfaceCheckCount = surfaceCheckCount

        guard let point = horizontalSurfacePoint(in: uiView) else {
            return
        }

        var checkMessage = "Surface detected"

        let anchor = AnchorEntity(world: point)

        let radius: Float = 0.04
        let marker = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: .yellow, isMetallic: false)])

        marker.position.y = radius
        anchor.addChild(marker)
        uiView.scene.addAnchor(anchor)

        if routeStartOffset != nil {
            guard let frame = uiView.session.currentFrame else {
                return
            }

            let cameraPosition = frame.camera.transform.columns.3

            let routeStartPosition = SIMD3<Float>(cameraPosition.x, point.y, cameraPosition.z)

            let routeAnchor = AnchorEntity(world: routeStartPosition)

            let routeDisplay = context.coordinator.routeDisplay

            for child in Array(routeDisplay.children) {
                child.removeFromParent()
            }

            routeAnchor.addChild(routeDisplay)

            let routeMarker = ModelEntity(
                mesh: .generateSphere(radius: 0.05),
                materials: [SimpleMaterial(color: .blue, isMetallic: false)])

            routeMarker.position.y = 0.05
            routeAnchor.addChild(routeMarker)

            if let nextPoint = localRoutePoints.first(where: { point in
                hypot(point.eastMeters, point.northMeters) > 0.01
            }) {
                let offset = nextPoint.arOffset
                let length = hypot(offset.x, offset.z)

                let routeDegrees = atan2(nextPoint.eastMeters, nextPoint.northMeters) * 180 / Double.pi
                let routeBearing = (routeDegrees + 360).truncatingRemainder(dividingBy: 360)

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

            }

            context.coordinator.routeAnchor?.removeFromParent()

            uiView.scene.addAnchor(routeAnchor)
            context.coordinator.routeAnchor = routeAnchor

            context.coordinator.routePoints = localRoutePoints.map { routePoint in
                routePoint.arOffset
            }

            // Initial placement uses the same bend-preserving drawing as walking updates.
            context.coordinator.redrawRoute(from: 0)
            context.coordinator.resetRouteDisplayProgress()
        }

        if let startOffset = routeStartOffset {
            let horizontalDistance = hypot(startOffset.eastMeters, startOffset.northMeters)

            checkMessage += String(
                format: "\nStart offset · East: %.1f m · North: %.1f m · Total: %.1f m",
                startOffset.eastMeters, startOffset.northMeters, horizontalDistance)
        }

        Task { @MainActor in
            detectedSurfacePoint = point
            checkMessage += "\nStand still and point along the sidewalk to align automatically."
            surfaceMessage = checkMessage
        }
    }

    /// Pauses camera tracking when this navigation view is removed.
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    /// Owns route projection, drawing, calibration, and interrupted-session recovery.
    class Coordinator: NSObject, ARSessionDelegate {
        private let trackingMessage: Binding<String>
        private let distanceFromRouteBinding: Binding<Float?>
        private var routeProgressMeters: Binding<Float?>
        private let surfaceMessage: Binding<String>
        /// Connects coordinator feedback to the navigation screen’s state.
        init(
            trackingMessage: Binding<String>, routeProgressMeters: Binding<Float?>,
            distanceFromRouteMeters: Binding<Float?>, surfaceMessage: Binding<String>
        ) {
            self.trackingMessage = trackingMessage
            self.routeProgressMeters = routeProgressMeters
            self.distanceFromRouteBinding = distanceFromRouteMeters
            self.surfaceMessage = surfaceMessage
        }

        var lastSurfaceCheckCount = 0
        var lastAlignmentRequestCount = 0
        private var lastAlignmentTimestamp: TimeInterval?
        private var hasAutomaticallyAligned = false
        private var alignmentCandidate: (heading: Float, timestamp: TimeInterval)?
        private var arOffsetStartedAt: TimeInterval?
        private var hasSustainedAROffset = false
        var gpsSupportsRealignment: () -> Bool = { false }

        var routeAnchor: AnchorEntity? = nil
        var routePoints: [SIMD3<Float>] = []
        var cameraRoutePosition: SIMD3<Float>? = nil
        private(set) var distanceFromRouteMeters: Float? = nil
        let routeDisplay = Entity()
        private var lastDrawnProgress: Float? = nil
        private var requiresRouteRecovery = false
        // Saved progress supports deliberate recovery when the public progress is temporarily unavailable.
        private var lastReliableProgress: Float?
        private var walkingDirectionStart: (position: SIMD3<Float>, timestamp: TimeInterval)?

        /// Hides stale guidance while retaining progress for deliberate manual recovery.
        private func requireRouteRecovery() {
            requiresRouteRecovery = true

            routeDisplay.isEnabled = false
            routeProgressMeters.wrappedValue = nil
            distanceFromRouteBinding.wrappedValue = nil
            lastDrawnProgress = nil

            alignmentCandidate = nil
            walkingDirectionStart = nil
            arOffsetStartedAt = nil
            hasSustainedAROffset = false

            surfaceMessage.wrappedValue =
                "AR was interrupted. Wait for tracking, then stand on the walkway and tap Align Route."
        }

        /// Invalidates placement when ARKit reports a session interruption.
        func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                self.requireRouteRecovery()
            }
        }

        /// Keeps placement invalid until a manual alignment verifies recovery.
        func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                self.requiresRouteRecovery = true

                self.surfaceMessage.wrappedValue =
                    "Camera tracking is recovering. When ready, face along the walkway and tap Align Route."
            }
        }

        /// Publishes tracking readiness independently of route placement.
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

            Task { @MainActor in
                self.trackingMessage.wrappedValue = message
            }
        }

        /// Projects and draws each frame together on the main actor to avoid stale anchor calculations.
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Keep projection and anchor changes in the same main-actor operation.
            Task { @MainActor in
                guard let routeAnchor = self.routeAnchor else {
                    return
                }

                let translation = frame.camera.transform.columns.3
                let worldPosition = SIMD3<Float>(translation.x, translation.y, translation.z)

                self.cameraRoutePosition = routeAnchor.convert(position: worldPosition, from: nil)

                let progress: Float?

                if case .normal = frame.camera.trackingState, !self.requiresRouteRecovery,
                    let position = self.cameraRoutePosition
                {
                    progress = self.nearestRouteProgress(to: position)
                } else {
                    progress = nil
                }
                if let progress {
                    self.lastReliableProgress = progress
                }
                let sidewaysDistance = progress != nil ? distanceFromRouteMeters : nil

                self.distanceFromRouteBinding.wrappedValue = sidewaysDistance
                self.routeProgressMeters.wrappedValue = progress
                self.updateAROffsetEvidence(distance: sidewaysDistance, timestamp: frame.timestamp)
                if !self.hasAutomaticallyAligned {
                    if let progress, self.routeDirection(at: progress) != nil {
                        if self.hasSteadyAlignmentHeading(in: frame) {
                            let result = self.alignRoute(in: frame)
                            self.surfaceMessage.wrappedValue = result.message

                            if result.didAlign {
                                return
                            }
                        }
                    } else {
                        self.alignmentCandidate = nil
                    }
                }

                if self.correctAROffsetIfNeeded(in: frame, progress: progress) {
                    return
                }

                guard let progress = progress else {
                    self.routeDisplay.isEnabled = false
                    self.lastDrawnProgress = nil
                    return
                }

                self.routeDisplay.isEnabled = true

                if let previous = self.lastDrawnProgress, abs(progress - previous) < 0.1 {
                    return
                }

                self.redrawRoute(from: progress)
                self.lastDrawnProgress = progress
            }

        }

        /// Projects horizontally and clamps the result to the finite segment.
        private func fractionAlongSegment(position: SIMD3<Float>, start: SIMD3<Float>, end: SIMD3<Float>)
            -> Float
        {

            let segment = end - start
            let toPhone = position - start
            let lengthSquared = segment.x * segment.x + segment.z * segment.z

            guard lengthSquared > 0 else {
                return 0
            }

            // Project onto the horizontal segment; phone height should not affect walking progress.
            let fraction = (toPhone.x * segment.x + toPhone.z * segment.z) / lengthSquared

            return min(max(fraction, 0), 1)
        }

        /// Returns progress at the nearest route point, allowing transitions through bends.
        private func nearestRouteProgress(to position: SIMD3<Float>) -> Float? {
            distanceFromRouteMeters = nil
            guard routePoints.count >= 2 else {
                return nil
            }

            var distanceBeforeSegment: Float = 0
            var closestDistance = Float.infinity
            var bestProgress: Float? = nil

            for (start, end) in zip(routePoints, routePoints.dropFirst()) {
                let segment = end - start
                let segmentLength = hypot(segment.x, segment.z)
                guard segmentLength > 0 else { continue }

                let fraction = fractionAlongSegment(
                    position: position,
                    start: start,
                    end: end
                )
                let closestPoint = start + segment * fraction
                let distanceToPhone = hypot(
                    position.x - closestPoint.x,
                    position.z - closestPoint.z
                )

                // The nearest-point search allows backtracking, but nearby route sections can still cause jumps.
                if distanceToPhone < closestDistance {
                    closestDistance = distanceToPhone
                    bestProgress = distanceBeforeSegment + segmentLength * fraction
                }

                distanceBeforeSegment += segmentLength
            }

            if bestProgress != nil {
                distanceFromRouteMeters = closestDistance
            }

            return bestProgress
        }

        /// Interpolates a route point at a distance and clamps beyond the endpoint.
        private func pointAlongRoute(at distance: Float) -> SIMD3<Float>? {
            guard let first = routePoints.first else {
                return nil
            }

            if distance <= 0 {
                return first
            }

            var remaining = distance

            for (start, end) in zip(routePoints, routePoints.dropFirst()) {
                let segment = end - start
                let length = hypot(segment.x, segment.z)

                guard length > 0 else { continue }

                if remaining <= length {
                    let fraction = remaining / length
                    return start + segment * fraction
                }

                remaining -= length
            }

            return routePoints.last
        }

        /// Collects the guidance window endpoints and every bend inside that window.
        private func visibleRoutepoints(from progress: Float, length: Float) -> [SIMD3<Float>] {
            guard length > 0 else { return [] }

            let startDistance = max(0, progress)
            let endDistance = startDistance + length

            guard let startPoint = pointAlongRoute(at: startDistance),
                let endPoint = pointAlongRoute(at: endDistance)
            else {
                return []
            }

            var points = [startPoint]
            var distanceAlongRoute: Float = 0

            for (start, end) in zip(routePoints, routePoints.dropFirst()) {
                let segment = end - start
                let segmentLength = hypot(segment.x, segment.z)

                guard segmentLength > 0 else { continue }

                distanceAlongRoute += segmentLength

                // Preserve all bend vertices inside the five-meter window, rather than drawing across corners.
                if distanceAlongRoute > startDistance,
                    distanceAlongRoute < endDistance
                {
                    points.append(end)
                }

                if distanceAlongRoute >= endDistance {
                    break
                }

            }

            if let last = points.last, hypot(endPoint.x - last.x, endPoint.z - last.z) > 0 {
                points.append(endPoint)
            }

            return points
        }

        /// Rebuilds the short route strip and marks its visible endpoint.
        func redrawRoute(from progress: Float) {
            let points = visibleRoutepoints(from: progress, length: 5)

            for child in Array(routeDisplay.children) {
                child.removeFromParent()
            }

            guard points.count >= 2 else { return }

            for (start, end) in zip(points, points.dropFirst()) {
                let segment = end - start
                let length = hypot(segment.x, segment.z)

                guard length > 0 else { continue }

                let strip = ModelEntity(
                    mesh: .generateBox(size: SIMD3<Float>(0.12, 0.01, length)),
                    materials: [SimpleMaterial(color: .yellow, isMetallic: false)])

                strip.position = SIMD3<Float>((start.x + end.x) / 2, 0.015, (start.z + end.z) / 2)

                let angle = atan2(segment.x, segment.z)
                // Rotate the box’s long axis to follow the segment in the horizontal plane.
                strip.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))

                routeDisplay.addChild(strip)

            }

            if let last = points.last {
                let marker = ModelEntity(
                    mesh: .generateSphere(radius: 0.05),
                    materials: [SimpleMaterial(color: .green, isMetallic: false)])

                marker.position = SIMD3<Float>(last.x, 0.05, last.z)
                routeDisplay.addChild(marker)
            }
        }

        /// Requires enough roughly straight route ahead before changing its heading.
        private func routeDirection(at progress: Float) -> SIMD3<Float>? {
            guard progress >= 0 else {
                return nil
            }

            var distanceBeforeSegment: Float = 0
            var checkedDistance: Float = 0
            var referenceDirection: SIMD3<Float>? = nil

            let requiredDistance: Float = 5
            // For unit directions, the dot product is the cosine of the angle between them.
            let minimumDotProduct = cos(Float.pi / 18)

            for (start, end) in zip(routePoints, routePoints.dropFirst()) {
                let segment = end - start
                let length = hypot(segment.x, segment.z)

                guard length > 0 else {
                    continue
                }

                let segmentEnd = distanceBeforeSegment + length

                if segmentEnd <= progress {
                    distanceBeforeSegment = segmentEnd
                    continue
                }

                let direction = segment / length

                if referenceDirection == nil {
                    referenceDirection = direction
                }

                guard let referenceDirection = referenceDirection else {
                    return nil
                }

                let dotProduct = referenceDirection.x * direction.x + referenceDirection.z * direction.z

                guard dotProduct >= minimumDotProduct else {
                    return nil
                }

                let availableLength = segmentEnd - max(progress, distanceBeforeSegment)

                checkedDistance += availableLength

                if checkedDistance >= requiredDistance {
                    return referenceDirection
                }

                distanceBeforeSegment = segmentEnd
            }

            return nil
        }

        /// Requires a stable horizontal camera heading before initial automatic alignment.
        private func hasSteadyAlignmentHeading(in frame: ARFrame) -> Bool {
            guard case .normal = frame.camera.trackingState else {
                alignmentCandidate = nil
                return false
            }
            let cameraZ = frame.camera.transform.columns.2
            let forwardX = -cameraZ.x
            let forwardZ = -cameraZ.z

            guard hypot(forwardX, forwardZ) > 0.3 else {
                alignmentCandidate = nil
                return false
            }

            let heading = atan2(forwardX, forwardZ)

            guard let candidate = alignmentCandidate else {
                alignmentCandidate = (heading, frame.timestamp)
                return false
            }

            let difference = heading - candidate.heading
            // Wrap the difference at ±180 degrees so crossing north/south angle boundaries is measured correctly.
            let headingChange = abs(atan2(sin(difference), cos(difference))) * 180 / Float.pi
            if headingChange > 3 {
                alignmentCandidate = (heading, frame.timestamp)
                return false
            }

            return frame.timestamp - candidate.timestamp >= 1.0
        }

        /// Places the current route point beneath the camera and verifies horizontal placement.
        func alignRoute(in frame: ARFrame, walkingDirection: SIMD3<Float>? = nil) -> (
            didAlign: Bool, message: String
        ) {
            guard let anchor = routeAnchor,
                let progress = routeProgressMeters.wrappedValue ?? lastReliableProgress,
                let routePoint = pointAlongRoute(at: progress)
            else {
                return (false, "Wait for the route to be placed before aligning.")
            }

            guard case .normal = frame.camera.trackingState else {
                return (false, "Wait for camera tracking to be ready.")
            }

            let direction = routeDirection(at: progress)

            // Recovery near a bend preserves heading while restoring horizontal placement.
            let recoveringNearTurn =
                requiresRouteRecovery && walkingDirection == nil && direction == nil

            guard direction != nil || recoveringNearTurn else {
                return (false, "Align on a straight section, at least five meters before the next bend.")
            }

            let targetDirection: SIMD3<Float>

            if let walkingDirection {
                targetDirection = walkingDirection
            } else {
                let cameraZ = frame.camera.transform.columns.2
                targetDirection = SIMD3<Float>(-cameraZ.x, 0, -cameraZ.z)
            }

            let horizontalLength = hypot(targetDirection.x, targetDirection.z)

            guard horizontalLength > 0.3 else {
                return (false, "Point your phone farther ahead along the walkway.")
            }

            let rotation: simd_quatf

            if let direction {
                let targetAngle = atan2(targetDirection.x, targetDirection.z)
                let routeAngle = atan2(direction.x, direction.z)
                rotation = simd_quatf(
                    angle: targetAngle - routeAngle,
                    axis: SIMD3<Float>(0, 1, 0)
                )
            } else {
                rotation = anchor.orientation(relativeTo: nil)
            }

            let cameraPosition = frame.camera.transform.columns.3
            // The camera and rotated route point must share world coordinates.
            let rotatedRoutePoint = rotation.act(routePoint)
            let groundHeight = anchor.position(relativeTo: nil).y

            anchor.setOrientation(rotation, relativeTo: nil)

            anchor.setPosition(
                SIMD3<Float>(
                    cameraPosition.x - rotatedRoutePoint.x,
                    groundHeight,
                    cameraPosition.z - rotatedRoutePoint.z
                ), relativeTo: nil)

            let cameraWorldPosition = SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            // Verify the camera against the intended route point after applying the world-space transform.
            let cameraAfterAlignment = anchor.convert(position: cameraWorldPosition, from: nil)
            let horizontalError = hypot(
                cameraAfterAlignment.x - routePoint.x,
                cameraAfterAlignment.z - routePoint.z
            )

            cameraRoutePosition = cameraAfterAlignment
            distanceFromRouteMeters = horizontalError
            distanceFromRouteBinding.wrappedValue = horizontalError

            guard horizontalError < 0.25 else {
                requiresRouteRecovery = true
                routeDisplay.isEnabled = false
                routeProgressMeters.wrappedValue = nil

                return (
                    false,
                    "Route placement could not be verified. Use View Map."
                )
            }
            requiresRouteRecovery = false
            // Restore the accepted progress only after placement verification succeeds.
            lastReliableProgress = progress
            routeProgressMeters.wrappedValue = progress
            redrawRoute(from: progress)
            routeDisplay.isEnabled = true
            lastDrawnProgress = progress
            hasAutomaticallyAligned = true
            alignmentCandidate = nil

            lastAlignmentTimestamp = frame.timestamp
            walkingDirectionStart = nil
            arOffsetStartedAt = nil
            hasSustainedAROffset = false

            if recoveringNearTurn {
                return (
                    true,
                    "Route repositioned. Follow the turn, then align on a straight section if needed."
                )
            }

            return (true, String(format: "Route Aligned at %.1f m. Progress Preserved", progress))
        }

        /// Forces the next usable frame to redraw guidance after placement.
        func resetRouteDisplayProgress() {
            lastDrawnProgress = nil
        }

        /// Tracks sustained lateral displacement while usable AR progress is available.
        private func updateAROffsetEvidence(distance: Float?, timestamp: TimeInterval) {
            guard let distance, distance >= 0.8 else {
                arOffsetStartedAt = nil
                hasSustainedAROffset = false
                return
            }

            guard let startedAt = arOffsetStartedAt else {
                arOffsetStartedAt = timestamp
                return
            }

            hasSustainedAROffset = timestamp - startedAt >= 3.0
        }

        /// Estimates horizontal travel direction from displacement within a short time window.
        private func sampleWalkingDirection(in frame: ARFrame) -> SIMD3<Float>? {

            guard case .normal = frame.camera.trackingState else {
                walkingDirectionStart = nil
                return nil
            }

            let translation = frame.camera.transform.columns.3
            let position = SIMD3<Float>(translation.x, 0, translation.z)

            guard let start = walkingDirectionStart else {
                walkingDirectionStart = (position, frame.timestamp)
                return nil
            }

            if frame.timestamp - start.timestamp > 8 {
                walkingDirectionStart = (position, frame.timestamp)
                return nil
            }

            // Net displacement estimates travel direction; it does not yet verify a straight trajectory.
            let movement = position - start.position
            let distance = hypot(movement.x, movement.z)

            guard distance >= 3 else {
                return nil
            }

            walkingDirectionStart = (position, frame.timestamp)

            return movement / distance
        }

        /// Attempts correction only when GPS, movement direction, and cooldown checks pass.
        private func correctAROffsetIfNeeded(in frame: ARFrame, progress: Float?) -> Bool {

            let walkingDirection = sampleWalkingDirection(in: frame)

            guard hasAutomaticallyAligned, hasSustainedAROffset,
                let walkingDirection, let progress,
                let anchor = routeAnchor, let lastAlignmentTimestamp,
                let routeDirection = routeDirection(at: progress),
                frame.timestamp - lastAlignmentTimestamp >= 5
            else {
                return false
            }

            // Compare both directions in world coordinates, including the route’s current calibration.
            let displayedDirection = anchor.orientation(relativeTo: nil).act(routeDirection)
            let agreement =
                displayedDirection.x * walkingDirection.x + displayedDirection.z * walkingDirection.z

            guard agreement >= cos(20 * Float.pi / 180), gpsSupportsRealignment() else {
                return false
            }

            let result = alignRoute(in: frame, walkingDirection: walkingDirection)

            if result.didAlign {
                surfaceMessage.wrappedValue = "Route realigned using your walking direction."
            }

            return result.didAlign

        }
    }

    /// Creates the persistent route coordinator with navigation feedback bindings.
    func makeCoordinator() -> Coordinator {
        Coordinator(
            trackingMessage: $trackingMessage, routeProgressMeters: $routeProgressMeters,
            distanceFromRouteMeters: $distanceFromRouteMeters, surfaceMessage: $surfaceMessage)
    }

    /// Raycasts the screen center against an existing horizontal plane.
    private func horizontalSurfacePoint(in arView: ARView) -> SIMD3<Float>? {

        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard
            let hit = arView.raycast(
                from: screenCenter, allowing: .existingPlaneGeometry, alignment: .horizontal
            ).first
        else {
            return nil
        }
        let position = hit.worldTransform.columns.3
        return SIMD3<Float>(position.x, position.y, position.z)

    }
}
