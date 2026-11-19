import CoreLocation
import MapKit
import SwiftUI

/// Coordinates AR controls, GPS route evidence, arrival, and the fallback map.
struct ARNavigationView: View {
    let destinationName: String
    let routeCoordinates: [CLLocationCoordinate2D]
    let startLocation: CLLocation
    let locationManager: LocationManager
    let rerouteMessage: String?
    let routeStartDiagnostic: String
    let onReroute: () -> Bool
    @State private var trackingMessage = "Starting AR tracking…"
    @State private var isShowingRouteMap = false
    @State private var lastUsableMapProgress: Double?
    @State private var mapOpenedAutomatically = false

    @State private var surfaceCheckCount = 0
    @State private var alignmentRequestCount = 0
    @State private var surfaceMessage =
        "Stand still and tilt your phone down until the walkway is in the center of the screen."
    @State private var detectedSurfacePoint: SIMD3<Float>? = nil

    @State private var routeProgressMeters: Float? = nil
    @State private var distanceFromRouteMeters: Float? = nil
    @State private var lastGPSFixTimestamp: Date?
    @State private var consecutiveOffRouteGPSFixes = 0
    @State private var lastRerouteAttempt: Date?
    @State private var hasArrived = false

    @Environment(\.dismiss) private var dismiss

    /// Measures the mapped start relative to the captured GPS fix for placement diagnostics.
    private var routeStartOffset: LocalRoutePoint? {
        guard let routeStart = routeCoordinates.first else {
            return nil
        }

        return LocalRoutePoint.from(coordinate: routeStart, relativeTo: startLocation.coordinate)
    }

    /// Converts a recent, sufficiently accurate GPS fix into the route’s local coordinates.
    private var currentGPSRoutePoint: LocalRoutePoint? {
        guard let location = locationManager.currentLocation,
            let routeOrigin = routeCoordinates.first
        else {
            return nil
        }
        let age = Date().timeIntervalSince(location.timestamp)
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 10, age >= -5, age <= 15 else {
            return nil
        }

        return LocalRoutePoint.from(coordinate: location.coordinate, relativeTo: routeOrigin)
    }

    /// Finds the nearest mapped point and returns both along-route progress and lateral distance.
    private var gpsRouteMatch: (progress: Double, distance: Double)? {
        guard let gpsPoint = currentGPSRoutePoint,
            let origin = routeCoordinates.first, routeCoordinates.count >= 2
        else {
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

            // Clamp to the finite segment, then compare lateral distances across the whole route.
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

    /// Requires stronger GPS evidence before allowing automatic overlay correction.
    private var gpsSupportsARRealignment: Bool {
        guard let location = locationManager.currentLocation,
            let match = gpsRouteMatch
        else {
            return false
        }

        let age = Date().timeIntervalSince(location.timestamp)

        guard age >= -5, age <= 5, location.horizontalAccuracy <= 5 else {
            return false
        }

        return match.distance <= 5
    }

    /// Checks the off-route streak against the current fix and its freshness.
    private var hasConfirmedRouteDeviation: Bool {
        guard consecutiveOffRouteGPSFixes >= 3,
            let location = locationManager.currentLocation,
            let lastGPSFixTimestamp,
            location.timestamp == lastGPSFixTimestamp
        else {
            return false
        }

        let age = Date().timeIntervalSince(location.timestamp)
        return age >= -5 && age <= 5
    }

    /// Trims completed geometry using cached GPS progress, retaining it during GPS gaps.
    private var remainingMapRouteCoordinates: [CLLocationCoordinate2D] {
        guard let origin = routeCoordinates.first, let progress = lastUsableMapProgress else {
            return routeCoordinates
        }

        var distanceBeforeSegment = 0.0

        for index in routeCoordinates.indices.dropLast() {
            let start = routeCoordinates[index]
            let end = routeCoordinates[index + 1]

            let localStart = LocalRoutePoint.from(coordinate: start, relativeTo: origin)
            let localEnd = LocalRoutePoint.from(coordinate: end, relativeTo: origin)
            let length = hypot(
                localEnd.eastMeters - localStart.eastMeters, localEnd.northMeters - localStart.northMeters)

            guard length > 0 else { continue }
            let segmentEnd = distanceBeforeSegment + length
            if progress < segmentEnd {

                // Interpolate the new first point so the remaining line begins at the last accepted GPS progress.
                let fraction = (progress - distanceBeforeSegment) / length
                let matchedCoordinate = CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
                return [matchedCoordinate] + Array(routeCoordinates.dropFirst(index + 1))
            }

            distanceBeforeSegment = segmentEnd
        }
        return []
    }

    /// Adds horizontal segment lengths using the same coordinates as GPS projection.
    private var totalRouteMeters: Double? {
        guard let origin = routeCoordinates.first, routeCoordinates.count >= 2 else {
            return nil
        }

        let points = routeCoordinates.map { LocalRoutePoint.from(coordinate: $0, relativeTo: origin) }
        var totalMeters = 0.0

        for (start, end) in zip(points, points.dropFirst()) {
            totalMeters += hypot(end.eastMeters - start.eastMeters, end.northMeters - start.northMeters)
        }
        return totalMeters
    }

    /// Subtracts the last usable GPS progress from the route length.
    private var remainingRouteMeters: Double? {
        guard let totalMeters = totalRouteMeters else { return nil }
        let progress = lastUsableMapProgress ?? 0
        return max(0, totalMeters - progress)
    }

    /// Requires a fresh fix near both the endpoint and the end of the route.
    private var meetsArrivalConditions: Bool {
        guard let endpoint = routeCoordinates.last,
            let fix = locationManager.currentLocation,
            let match = gpsRouteMatch,
            let totalMeters = totalRouteMeters
        else {
            return false
        }

        let age = Date().timeIntervalSince(fix.timestamp)
        guard age >= -5, age <= 5 else { return false }

        let destinationLocation = CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude)

        let distanceToEndpoint = fix.distance(from: destinationLocation)
        // Endpoint proximity alone can trigger early on a route that passes close to its destination.
        let metersLeftOnRoute = max(0, totalMeters - match.progress)

        return distanceToEndpoint <= 8 && metersLeftOnRoute <= 10
    }

    /// Counts distinct off-route fixes and breaks the streak after invalid fixes or long gaps.
    private func updateGPSDeviationEvidence() {
        guard let location = locationManager.currentLocation,
            let match = gpsRouteMatch
        else {
            lastGPSFixTimestamp = nil
            consecutiveOffRouteGPSFixes = 0
            return
        }

        let timestamp = location.timestamp

        if let previousTimestamp = lastGPSFixTimestamp {
            // Repeated or out-of-order readings must not count as additional off-route evidence.
            guard timestamp > previousTimestamp else { return }

            if timestamp.timeIntervalSince(previousTimestamp) > 5 {
                consecutiveOffRouteGPSFixes = 0
            }
        }

        lastGPSFixTimestamp = timestamp

        // Allow the reported GPS uncertainty plus a margin before counting a possible departure.
        let offRouteThreshold = location.horizontalAccuracy + 5.0

        if match.distance > offRouteThreshold {
            consecutiveOffRouteGPSFixes += 1
        } else {
            consecutiveOffRouteGPSFixes = 0
        }
    }

    /// Requests replacement guidance after confirmed deviation, with a retry cooldown.
    private func rerouteIfNeeded() {
        guard hasConfirmedRouteDeviation else { return }

        let now = Date()

        if let lastRerouteAttempt, now.timeIntervalSince(lastRerouteAttempt) < 10 {
            return
        }

        // Failures also start the cooldown so each incoming GPS fix cannot immediately retry.
        lastRerouteAttempt = now

        if !onReroute() {
            surfaceMessage = "Couldn't find a new route from your current location"
        }

    }

    /// Keeps each distance, time, or arrival estimate readable in its own card.
    private func summaryBox<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 4) {
            content()
                .font(.headline)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    /// Shares remaining-distance estimates and arrival controls between AR and the map.
    private var navigationSummary: some View {
        if hasArrived {
            VStack(spacing: 8) {
                Text("You’ve arrived")
                    .font(.headline)

                Text(destinationName)

                Button("End Navigation") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if let meters = remainingRouteMeters {
            let secondsRemaining = meters / 1.4
            let minutesRemaining = Int(ceil(secondsRemaining / 60))
            let estimatedArrival = Date().addingTimeInterval(secondsRemaining)
            VStack {
                HStack(spacing: 8) {
                    summaryBox("Distance left") {
                        Text("\(meters, specifier: "%.0f") m")
                    }

                    summaryBox("Time left") {
                        Text("\(minutesRemaining) min")
                    }

                    summaryBox("Est. arrival") {
                        Text(estimatedArrival.formatted(date: .omitted, time: .shortened))
                    }
                }
                .padding(.horizontal, 8)

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
            }
        }
    }

    /// Defers fallback before placement or after arrival; otherwise reports progress availability.
    private var arGuidanceAvailable: Bool? {
        guard detectedSurfacePoint != nil, !hasArrived else {
            return nil
        }

        return routeProgressMeters != nil
    }

    /// Presents AR guidance and controls, and reacts to location, tracking, and map-sheet changes.
    var body: some View {
        ZStack {
            ARCameraView(
                trackingMessage: $trackingMessage, routeCoordinates: routeCoordinates,
                surfaceCheckCount: surfaceCheckCount, surfaceMessage: $surfaceMessage,
                detectedSurfacePoint: $detectedSurfacePoint, routeProgressMeters: $routeProgressMeters,
                distanceFromRouteMeters: $distanceFromRouteMeters, routeStartOffset: routeStartOffset,
                alignmentRequestCount: alignmentRequestCount,
                gpsSupportsRealignment: { gpsSupportsARRealignment }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text(destinationName)
                        .foregroundStyle(.white)

                    Spacer()

                    Text(trackingMessage)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    Menu {
                        Button("View Map") {
                            mapOpenedAutomatically = false
                            isShowingRouteMap = true
                        }
                        Button("Exit Navigation", role: .destructive) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())

                    }
                    .accessibilityLabel("Navigation options")

                }

                navigationSummary
                Spacer()

                #if DEBUG

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
                .disabled(detectedSurfacePoint == nil)

                Text(surfaceMessage)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            }
            .padding()
        }
        // Changing availability cancels the old timer; manual map presentation must remain under user control.
        .task(id: arGuidanceAvailable) {
            guard let guidanceAvailable = arGuidanceAvailable else { return }

            do {
                if guidanceAvailable {
                    guard isShowingRouteMap, mapOpenedAutomatically else { return }

                    try await Task.sleep(for: .seconds(3))

                    guard !Task.isCancelled, arGuidanceAvailable == true,
                        isShowingRouteMap, mapOpenedAutomatically
                    else { return }

                    isShowingRouteMap = false
                } else {
                    guard !isShowingRouteMap else { return }

                    try await Task.sleep(for: .seconds(5))

                    guard !Task.isCancelled, arGuidanceAvailable == false,
                        !isShowingRouteMap
                    else { return }

                    mapOpenedAutomatically = true
                    isShowingRouteMap = true
                }
            } catch {
            }
        }
        .onChange(of: isShowingRouteMap) { _, isShowing in
            if !isShowing {
                mapOpenedAutomatically = false
            }
        }
        .sheet(isPresented: $isShowingRouteMap) {
            ARNavigationMapView(
                destinationName: destinationName,
                remainingCoordinates: remainingMapRouteCoordinates,
                endpoint: routeCoordinates.last,
                locationManager: locationManager,
                summary: navigationSummary,
                onBackToAR: { isShowingRouteMap = false }
            )
        }
        // Cache map progress first, latch arrival, and only then consider deviation and rerouting.
        .onChange(of: locationManager.currentLocation?.timestamp, initial: true) {
            if let match = gpsRouteMatch {
                lastUsableMapProgress = match.progress
            }
            if !hasArrived && meetsArrivalConditions {
                hasArrived = true
            }
            guard !hasArrived else { return }

            updateGPSDeviationEvidence()
            rerouteIfNeeded()
        }
        .task(id: detectedSurfacePoint == nil) {
            guard detectedSurfacePoint == nil else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                surfaceCheckCount += 1
            }
        }
    }
}
