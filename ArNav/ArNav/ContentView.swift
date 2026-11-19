import MapKit
import SwiftUI

/// A searchable campus destination with optional walking-network arrival nodes.
struct Destination: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var arrivalNodeID: String? = nil
    var arrivalCandidateNodeIDs: [String] = []
}

/// Owns destination selection, local routing, and presentation of a navigation session.
struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var locationManager = LocationManager()
    @State private var mapHeading: Double = 0
    @State private var routeMessage: String? = nil
    @State private var selectedMapDestinationID: String? = nil

    /// Resolves the selected marker ID to its destination record.
    private var selectedDestination: Destination? {
        destinationRecords.first { $0.id == selectedMapDestinationID }
    }

    @State private var searchText: String = ""

    @State private var destinationRecords: [Destination] = []
    @State private var selectedRouteDistance: Double? = nil
    @State private var lastRouteCalculationLocation: CLLocation? = nil
    @State private var routeStartNeedsConfirmation = false
    @State private var alternateStartCoordinates: [CLLocationCoordinate2D] = []
    @State private var isShowingStartConfirmation = false
    @State private var shouldOpenARAfterStartReview = false
    @State private var latestRouteStartDiagnostic = ""
    @State private var activeRouteStartDiagnostic = ""

    @State private var recentDestinationIDs: [String] =
        UserDefaults.standard.stringArray(forKey: "recentDestinationIDs") ?? []

    @State private var suggestedDestinationIDs: [String] = []

    @State private var walkingGraph: [String: [WalkingEdge]] = [:]
    @State private var selectedRoute: [WalkingEdge]? = nil
    @State private var walkingNodeCoordinates: [String: CLLocationCoordinate2D] = [:]

    @State private var cameraPermissionManager = CameraPermissionManager()
    @State private var cameraPermissionMessage: String? = nil

    @State private var isShowingARNavigation = false
    @State private var arStartLocation: CLLocation? = nil
    @State private var arRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var pendingAlternateStartCoordinates: [CLLocationCoordinate2D] = []
    @State private var arRouteSessionID = UUID()
    @State private var arRerouteMessage: String? = nil

    @FocusState private var isSearchFocused: Bool

    /// Restores recent selections that still exist in the bundled destination data.
    private var recentDestinations: [Destination] {
        recentDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }

    /// Resolves the current suggestion IDs for the search list.
    private var suggestedDestinations: [Destination] {
        suggestedDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }

    /// Shows recent or suggested places until the user enters a name to search.
    private var filteredDestinations: [Destination] {

        if searchText.isEmpty {

            if recentDestinations.isEmpty {

                return suggestedDestinations

            }

            return recentDestinations
        }

        return destinationRecords.filter { destination in
            destination.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let campusRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: 40.810890,
            longitude: -81.933880
        ),
        span: MKCoordinateSpan(
            latitudeDelta: 0.007,
            longitudeDelta: 0.007
        )
    )

    /// Calculates a preview and maintains up to five recent destination selections.
    private func selectDestination(id: String) {
        selectedMapDestinationID = id

        if let destination = destinationRecords.first(where: { destination in
            destination.id == id
        }) {
            calculateRoute(to: destination)
        } else {
            selectedRoute = nil
        }

        recentDestinationIDs.removeAll { recentID in
            recentID == id
        }

        recentDestinationIDs.insert(id, at: 0)

        if recentDestinationIDs.count > 5 {
            recentDestinationIDs.removeLast()
        }

        UserDefaults.standard.set(recentDestinationIDs, forKey: "recentDestinationIDs")

        isSearchFocused = false
    }

    /// Calculates a candidate route in a copied graph without replacing the active preview.
    private func routeFromStart(
        _ startMatch: WalkingStartMatch, to destination: Destination, temporaryStartID: String
    ) -> (edges: [WalkingEdge], distance: Double)? {

        var routingGraph = walkingGraph
        let edge = startMatch.edge
        let fraction = startMatch.fractionAlongEdge

        // Connect the projected start to both ends, allowing travel in either direction along the edge.
        routingGraph[temporaryStartID] = [
            WalkingEdge(
                wayID: edge.wayID,
                fromNodeID: temporaryStartID,
                toNodeID: edge.fromNodeID,
                distanceMeters: fraction * edge.distanceMeters
            ),
            WalkingEdge(
                wayID: edge.wayID,
                fromNodeID: temporaryStartID,
                toNodeID: edge.toNodeID,
                distanceMeters: (1 - fraction) * edge.distanceMeters
            ),
        ]
        // An explicitly configured entrance overrides the connected building-outline candidates.
        let candidateNodeIDs = destination.arrivalNodeID.map { [$0] } ?? destination.arrivalCandidateNodeIDs
        let router = WalkingRouter()
        var bestRoute: (edges: [WalkingEdge], distance: Double)?

        for nodeID in candidateNodeIDs {
            guard
                let edges = router.findRoute(
                    from: temporaryStartID,
                    to: nodeID,
                    in: routingGraph
                )
            else {
                continue
            }

            let distance = edges.reduce(0.0) { $0 + $1.distanceMeters }

            if distance < (bestRoute?.distance ?? .infinity) {
                bestRoute = (edges: edges, distance: distance)
            }
        }
        return bestRoute
    }

    /// Samples an opening route position for comparing plausible starting paths.
    private func pointNearRouteStart(
        _ edges: [WalkingEdge], from start: CLLocationCoordinate2D, at distance: Double
    ) -> CLLocation? {
        var previous = MKMapPoint(start)
        var remaining = distance

        for edge in edges {
            guard let coordinate = walkingNodeCoordinates[edge.toNodeID] else {
                return nil
            }

            let next = MKMapPoint(coordinate)
            let length = previous.distance(to: next)
            guard length > 0 else { continue }

            if remaining <= length {
                let fraction = remaining / length
                let point = MKMapPoint(
                    x: previous.x + (next.x - previous.x) * fraction,
                    y: previous.y + (next.y - previous.y) * fraction
                ).coordinate

                return CLLocation(latitude: point.latitude, longitude: point.longitude)
            }

            remaining -= length
            previous = next
        }
        let endpoint = previous.coordinate
        return CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude)
    }

    /// Validates GPS, matches nearby walkways, and publishes a reachable route preview.
    private func calculateRoute(to destination: Destination, isRefresh: Bool = false) {

        if !isRefresh {
            selectedRoute = nil
            selectedRouteDistance = nil
            lastRouteCalculationLocation = nil
        }

        routeMessage = nil

        guard let location = locationManager.currentLocation else {
            showRouteFailure(
                "Your location is unavailable. Check Location access and wait for a reading",
                isRefresh: isRefresh
            )

            return
        }

        let age = Date().timeIntervalSince(location.timestamp)

        guard location.horizontalAccuracy >= 0, age >= -5, age <= 15 else {
            showRouteFailure(
                "Waiting for a recent, valid location. Try selecting your destination again shortly.",
                isRefresh: isRefresh
            )
            return
        }
        guard location.horizontalAccuracy <= 10 else {
            showRouteFailure(
                "Your location is too uncertain to choose a walking path. Move to an open area and try again.",
                isRefresh: isRefresh
            )

            return
        }

        let matcher = WalkingStartMatcher()

        var nearestMatch: WalkingStartMatch?
        var alternativeMatch: WalkingStartMatch?
        // The graph contains both directions of each physical segment; compare each segment only once.
        var seenSegments = Set<[String]>()

        for edges in walkingGraph.values {
            for edge in edges {
                let segmentKey = [edge.fromNodeID, edge.toNodeID].sorted()
                guard seenSegments.insert(segmentKey).inserted else {
                    continue
                }
                guard
                    let match = matcher.match(
                        location: location, to: edge, coordinates: walkingNodeCoordinates)
                else {
                    continue
                }
                if match.distanceFromUser < (nearestMatch?.distanceFromUser ?? .infinity) {
                    alternativeMatch = nearestMatch
                    nearestMatch = match
                } else if match.distanceFromUser < (alternativeMatch?.distanceFromUser ?? .infinity) {
                    alternativeMatch = match
                }
            }
        }

        guard let startMatch = nearestMatch else {
            showRouteFailure(
                "No mapped walking path was found.",
                isRefresh: isRefresh
            )

            return
        }

        guard startMatch.distanceFromUser <= 10 else {
            showRouteFailure(
                "Your reported location could not be matched closely enough to a mapped walking path.",
                isRefresh: isRefresh
            )
            return
        }
        let temporaryStartID = "temporary-user-start"

        if let result = routeFromStart(
            startMatch, to: destination, temporaryStartID: temporaryStartID
        ) {
            selectedRoute = result.edges
            selectedRouteDistance = result.distance
            walkingNodeCoordinates[temporaryStartID] = startMatch.coordinate
            lastRouteCalculationLocation = location
            latestRouteStartDiagnostic = String(
                format: "Start way: %@ · Path offset: %.1f m · GPS accuracy: %.1f m",
                startMatch.edge.wayID,
                startMatch.distanceFromUser,
                location.horizontalAccuracy
            )
            if let alternativeMatch {
                latestRouteStartDiagnostic += String(
                    format: "\nNext segment: way %@ · Path offset: %.1f m",
                    alternativeMatch.edge.wayID,
                    alternativeMatch.distanceFromUser
                )
            }
            routeStartNeedsConfirmation = false
            alternateStartCoordinates = []
        // Only compare a runner-up close enough to be plausible given the GPS uncertainty.
        let comparisonLimit = min(location.horizontalAccuracy + 1.0, 10.0)

            if let alternativeMatch,
                alternativeMatch.distanceFromUser <= comparisonLimit,
                let alternativeRoute = routeFromStart(
                    alternativeMatch,
                    to: destination,
                    temporaryStartID: temporaryStartID
                ),
                let primaryPoint = pointNearRouteStart(
                    result.edges, from: startMatch.coordinate, at: 5
                ),
                let alternativePoint = pointNearRouteStart(
                    alternativeRoute.edges, from: alternativeMatch.coordinate, at: 5
                )
            {
            // This compares one opening sample; routes that rejoin sooner may escape confirmation.
            let separation = primaryPoint.distance(from: alternativePoint)
                routeStartNeedsConfirmation = separation >= 3.0

                latestRouteStartDiagnostic += String(
                    format: "\nRoutes are %.1f m apart after 5 m",
                    separation
                )
                if routeStartNeedsConfirmation {
                    latestRouteStartDiagnostic += "\nStart confirmation recommended"
                    let endpoints = alternativeRoute.edges.compactMap {
                        walkingNodeCoordinates[$0.toNodeID]
                    }

                    if !endpoints.isEmpty, endpoints.count == alternativeRoute.edges.count {
                        alternateStartCoordinates = [alternativeMatch.coordinate] + endpoints
                    }
                }
            }

        } else {
            showRouteFailure(
                "No walking route is available to this destination in the current campus map.",
                isRefresh: isRefresh
            )
        }
    }

    /// Preserves the previous preview on refresh failure and explains its stale start.
    private func showRouteFailure(_ message: String, isRefresh: Bool) {
        if isRefresh && selectedRoute != nil {
            routeMessage =
                "\(message)\nShowing the previous route preview; its starting point, distance, and time have not been updated."
        } else {
            routeMessage = message
        }
    }

    /// Formats the preview distance in feet or miles for the destination card.
    private var selectedRouteDistanceText: String? {
        guard let meters = selectedRouteDistance else {
            return nil
        }

        let miles = meters / 1609.344

        if miles < 0.1 {
            let feet = meters / 0.3048
            let roundedFeet = (feet / 10).rounded() * 10

            return String(format: "%.0f ft", roundedFeet)
        }

        return String(format: "%.1f mi", miles)
    }

    private let walkingSpeedMetersPerSecond: Double = 1.4

    /// Estimates preview duration from route length and the configured walking speed.
    private var estimatedWalkingTimeSeconds: Double? {
        guard let distance = selectedRouteDistance else {
            return nil
        }

        return distance / walkingSpeedMetersPerSecond
    }

    /// Reconstructs the route polyline from ordered edge endpoints.
    private var selectedRouteCoordinates: [CLLocationCoordinate2D] {
        guard let route = selectedRoute,
            let firstEdge = route.first
        else {
            return []
        }

        var nodeIDs = [firstEdge.fromNodeID]
        for edge in route {
            nodeIDs.append(edge.toNodeID)
        }
        var coordinates: [CLLocationCoordinate2D] = []
        for nodeID in nodeIDs {
            guard let coordinate = walkingNodeCoordinates[nodeID] else {
                return []
            }

            coordinates.append(coordinate)
        }
        return coordinates
    }

    /// Replaces active guidance only after a new route is successfully calculated.
    private func recalculateActiveRoute(to destination: Destination) -> Bool {

        calculateRoute(to: destination, isRefresh: true)
        let coordinates = selectedRouteCoordinates

        guard routeMessage == nil,
            let routeLocation = lastRouteCalculationLocation,
            coordinates.count >= 2
        else {
            return false
        }

        arStartLocation = routeLocation
        arRouteCoordinates = coordinates
        activeRouteStartDiagnostic = latestRouteStartDiagnostic
        arRerouteMessage = "Route recalculated to \(destination.name)."
        // A new identity replaces the old AR coordinator and starts fresh placement for the replacement route.
        arRouteSessionID = UUID()
        return true
    }

    @MainActor
    /// Captures a fresh route and optionally asks the user to confirm an ambiguous start.
    private func startNavigation(to destination: Destination) async {
        let granted = await cameraPermissionManager.requestPermission()

        guard granted else {
            cameraPermissionMessage =
                "Camera access is unavailable. Check ArNav’s camera permission in Settings."
            return
        }

        cameraPermissionMessage = nil

        calculateRoute(to: destination)

        guard selectedRoute != nil,
            let routeLocation = lastRouteCalculationLocation
        else {
            return
        }

        arStartLocation = routeLocation
        arRouteCoordinates = selectedRouteCoordinates
        // Freeze both options before presenting the sheet so GPS preview updates cannot change the choice.
        pendingAlternateStartCoordinates = alternateStartCoordinates
        activeRouteStartDiagnostic = latestRouteStartDiagnostic
        arRerouteMessage = nil
        if routeStartNeedsConfirmation {
            isShowingStartConfirmation = true
        } else {
            isShowingARNavigation = true
        }

    }

    /// Composes destination browsing, route preview, start review, and AR presentation.
    var body: some View {

        ZStack(alignment: .top) {

            Map(
                initialPosition: .region(campusRegion),
                selection: $selectedMapDestinationID
            ) {
                if selectedRouteCoordinates.count >= 2 {
                    MapPolyline(coordinates: selectedRouteCoordinates)
                        .stroke(.blue, lineWidth: 5)
                }
                UserAnnotation {
                    ZStack {
                        if let heading = locationManager.headingDegrees {
                            HeadingCone(halfAngle: locationManager.headingHalfAngle)
                                .fill(.blue.opacity(0.3))
                                .rotationEffect(.degrees(heading - mapHeading))
                        }
                        Circle()
                            .fill(.blue)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            }
                    }
                    .frame(width: 100, height: 100)
                }

                ForEach(destinationRecords) { record in
                    Marker(record.name, coordinate: record.coordinate)
                        .tag(record.id)
                }
            }
            .onTapGesture {
                isSearchFocused = false
                selectedMapDestinationID = nil
                selectedRoute = nil
                selectedRouteDistance = nil
                routeMessage = nil
                lastRouteCalculationLocation = nil

            }
            .onChange(of: selectedMapDestinationID) { _, newID in
                if let id = newID {
                    selectDestination(id: id)
                }

            }
            .onMapCameraChange(frequency: .continuous) { context in
                mapHeading = context.camera.heading
            }

            if locationManager.authorizationStatus == .notDetermined {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("Enable my location") {
                            locationManager.requestPermission()
                        }
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))

                        Spacer()
                    }
                    Spacer()
                }

            } else if locationManager.authorizationStatus == .denied {

                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        Text(
                            "Location access is off. You can still browse destinations. Enable Location access in Settings to use your current location."
                        )
                        .font(.footnote)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))

                        Spacer()
                    }
                    Spacer()
                }

            } else if locationManager.authorizationStatus == .restricted {

                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        Text(
                            "Location access is restricted on this device. You can still browse destinations."
                        )
                        .font(.footnote)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))

                        Spacer()
                    }
                    Spacer()
                }

            }

            VStack(spacing: 2) {

                TextField("Search destinations", text: $searchText)
                    .focused($isSearchFocused)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .background(
                        Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 24)
                    )
                    .padding(.horizontal, 16)

                if let message = routeMessage {
                    Text(message)
                        .font(.footnote)
                        .padding(10)
                        .background(
                            .background,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }

                if isSearchFocused {

                    List {

                        if searchText.isEmpty {
                            if recentDestinations.isEmpty {
                                Text("Suggested destinations")
                                    .listRowBackground(Color.clear)
                            } else {
                                Text("Recent destinations")
                                    .listRowBackground(Color.clear)
                            }
                        } else {
                            Text("Search Results")
                                .listRowBackground(Color.clear)
                        }

                        if filteredDestinations.isEmpty {
                            Text("No Location Found")
                                .listRowBackground(Color.clear)
                        }

                        ForEach(filteredDestinations) { destination in

                            Button(destination.name) {
                                selectDestination(id: destination.id)

                            }
                            .listRowBackground(Color.clear)
                        }

                    }
                    .scrollContentBackground(.hidden)

                    .contentMargins(.top, 0, for: .scrollContent)

                    .frame(height: 300)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .background(
                        Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 24)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                }

            }
            VStack {
                Spacer()
                if let destination = selectedDestination {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(destination.name)
                            .font(.title2)
                            .bold()
                        HStack {
                            Spacer()
                            if let distanceText = selectedRouteDistanceText {
                                Text(distanceText)
                                    .padding(.bottom, 10)
                            }
                        }
                        HStack {
                            if let seconds = estimatedWalkingTimeSeconds {
                                Text("Estimated walk: \(seconds / 60, specifier: "%.1f") minutes")
                            }

                            Spacer()

                            Button {
                                Task {
                                    await startNavigation(to: destination)
                                }
                            } label: {
                                Text("Start")
                                    .fontWeight(.semibold)
                                    .frame(width: 110, height: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                            .disabled(selectedRoute == nil)
                        }

                        if let message = cameraPermissionMessage {
                            Text(message)
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .foregroundStyle(.white)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .background(
                        Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 24)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

        }
        .onAppear {

            if let fileURL = Bundle.main.url(
                forResource: "Campus-map",
                withExtension: "osm"
            ) {
                print("Campus map found:", fileURL)

                let loader = OSMDestinationLoader()

                if let parser = XMLParser(contentsOf: fileURL) {
                    parser.delegate = loader

                    if parser.parse() {

                        destinationRecords = loader.destinations

                        if suggestedDestinationIDs.isEmpty {
                            suggestedDestinationIDs =
                                destinationRecords
                                .shuffled()
                                .prefix(5)
                                .map { destination in
                                    destination.id
                                }
                        }

                        let walkingWays = loader.ways.filter { way in
                            way.tags["highway"] == "footway" || way.id == "297425916"
                        }

                        var walkingEdges: [WalkingEdge] = []

                        for way in walkingWays {

                            for (fromID, toID) in zip(way.nodeIDs, way.nodeIDs.dropFirst()) {

                                if let fromCoordinate = loader.nodeCoordinates[fromID],
                                    let toCoordinate = loader.nodeCoordinates[toID]
                                {

                                    let fromLocation = CLLocation(
                                        latitude: fromCoordinate.latitude, longitude: fromCoordinate.longitude
                                    )
                                    let toLocation = CLLocation(
                                        latitude: toCoordinate.latitude, longitude: toCoordinate.longitude)

                                    let distanceMeters = fromLocation.distance(from: toLocation)

                                    let edge = WalkingEdge(
                                        wayID: way.id, fromNodeID: fromID, toNodeID: toID,
                                        distanceMeters: distanceMeters)

                                    walkingEdges.append(edge)

                                    let reverseEdge = WalkingEdge(
                                        wayID: way.id, fromNodeID: toID, toNodeID: fromID,
                                        distanceMeters: distanceMeters)

                                    walkingEdges.append(reverseEdge)

                                } else {
                                    print("Missing coordinate for: ", fromID, toID)
                                }
                            }
                        }

                        print("Stores walking edges: ", walkingEdges.count)

                        // Group outgoing edges by source node for the shortest-path search.
                        let adjacency = Dictionary(grouping: walkingEdges, by: { edge in edge.fromNodeID })

                        walkingGraph = adjacency
                        walkingNodeCoordinates = loader.nodeCoordinates

                        for way in loader.ways {
                            if way.tags["building"] != nil {

                                // Only building-outline nodes shared with the walking graph are currently usable arrival candidates.
                                let sharedNodeIDs = Set(
                                    way.nodeIDs.filter { nodeID in
                                        adjacency[nodeID] != nil
                                    }
                                )

                                let destinationID = "osm-way-\(way.id)"

                                if let index = destinationRecords.firstIndex(where: { destination in
                                    destination.id == destinationID
                                }) {
                                    destinationRecords[index].arrivalCandidateNodeIDs = sharedNodeIDs.sorted()
                                }

                            }
                        }

                    } else {
                        print(
                            "XML parsing failed: ", parser.parserError?.localizedDescription ?? "Unkown error"
                        )
                    }
                } else {
                    print("Could not create the XML parser")
                }
            } else {
                print("Campus map file not found")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                locationManager.startUpdates()
            } else {
                locationManager.stopUpdates()
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            guard let location = newLocation,
                let destination = selectedDestination
            else {
                return
            }

            if let previousLocation = lastRouteCalculationLocation {
                let distanceMoved = location.distance(from: previousLocation)

                guard distanceMoved >= 5 else {
                    return
                }
            }

            calculateRoute(to: destination, isRefresh: true)
        }
        .sheet(
            isPresented: $isShowingStartConfirmation,
            onDismiss: {
                pendingAlternateStartCoordinates = []

                if shouldOpenARAfterStartReview {
                    shouldOpenARAfterStartReview = false
                    isShowingARNavigation = true
                }
            }
        ) {
            RouteStartReviewView(
                suggestedCoordinates: arRouteCoordinates,
                alternateCoordinates: pendingAlternateStartCoordinates,
                onUseSuggestedStart: {
                    shouldOpenARAfterStartReview = true
                    isShowingStartConfirmation = false
                },
                onUseOtherStart: {
                    arRouteCoordinates = pendingAlternateStartCoordinates
                    activeRouteStartDiagnostic = "Other start selected on the map."
                    shouldOpenARAfterStartReview = true
                    isShowingStartConfirmation = false
                },
                onCancel: { isShowingStartConfirmation = false }
            )
        }
        .fullScreenCover(isPresented: $isShowingARNavigation) {
            if let destination = selectedDestination, let location = arStartLocation {
                ARNavigationView(
                    destinationName: destination.name, routeCoordinates: arRouteCoordinates,
                    startLocation: location, locationManager: locationManager,
                    rerouteMessage: arRerouteMessage, routeStartDiagnostic: activeRouteStartDiagnostic,
                    onReroute: { recalculateActiveRoute(to: destination) }
                )
                .id(arRouteSessionID)
            }
        }

    }
}

#Preview {
    ContentView()

}
