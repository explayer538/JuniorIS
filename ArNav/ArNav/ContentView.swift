//
//  ContentView.swift
//  ArNav
//
//  Created by Franklin Adu-Baah on 9/24/26.
//

import SwiftUI
import MapKit

// Destination value Type with id, name and coordinate
struct Destination: Identifiable {
    // Identifies the building
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var arrivalNodeID: String? = nil
    var arrivalCandidateNodeIDs: [String] = []
}

struct ContentView: View {
    
    // Tracks whether the app scene is active, inactive or in background
    @Environment(\.scenePhase) private var scenePhase
    //Creating the Location Manager
    @State private var locationManger = LocationManager()
    @State private var mapHeading: Double = 0
    // Stores Explanation when routing cannot continue
    @State private var routeMessage: String? = nil
    //Selected Destination
    @State private var selectedMapDestinationID: String? = nil
    
    // Selected destinations variable that allow a null value
    private var selectedDestination: Destination? {
        destinationRecords.first { $0.id == selectedMapDestinationID}
    }
    
    // Search text variable which manages the filtering results and Text field display
    @State private var searchText: String = ""
    
    // record of destinations
    @State private var destinationRecords: [Destination] = []
    @State private var nearestNodeIDs: String? = nil
    @State private var nearestDistances: Double = 0.0
    @State private var selectedRouteDistance: Double? = nil
    @State private var lastRouteCalculationLocation: CLLocation? = nil
    @State private var routeStartNeedsConfirmation = false
    @State private var alternateStartCoordinates: [CLLocationCoordinate2D] = []
    @State private var isShowingStartConfirmation = false
    @State private var shouldOpenARAfterStartReview = false
    @State private var latestRouteStartDiagnostic = ""
    @State private var activeRouteStartDiagnostic = ""
    
    // Recent destination IDs that makes an Array if the is saved data for the key
    // if not intializes an empty array
    @State private var recentDestinationIDs: [String] = UserDefaults.standard.stringArray(forKey: "recentDestinationIDs") ?? []
    
    // An Array which stores the IDs of the suggested Destinations
    @State private var suggestedDestinationIDs: [String] = []
    
    // Walking graph for selected destination
    @State private var walkingGraph: [String: [WalkingEdge]] = [:]
    // Stores the selected route
    @State private var selectedRoute: [WalkingEdge]? = nil
    // Walking node coordinates
    @State private var walkingNodeCoordinates: [String: CLLocationCoordinate2D] = [:]
    
    // object that requests camera permission
    @State private var cameraPermissionManager = CameraPermissionManager()
    // holds feedback when camera access is not available
    @State private var cameraPermissionMessage: String? = nil
    
    @State private var isShowingARNavigarion = false
    @State private var arStartLocation: CLLocation? = nil
    @State private var arRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var pendingAlternateStartCoordinates: [CLLocationCoordinate2D] = []
    @State private var arRouteSessionID = UUID()
    @State private var arRerouteMessage: String? = nil
    
    //Text Field Tracking state
    @FocusState private var isSearchFocused: Bool
    
    //Variable that stores recently clicked locations
    private var recentDestinations: [Destination] {
        recentDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }
    
    // An array which stores the randomly selected suggested destinations
    private var suggestedDestinations: [Destination] {
        //create an array for Suggest IDs that match the destinations id
        suggestedDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }
    
    //List of filtered destinations which returns all destinations if the users has not typed anything and if the user has filters based on what the user has typed.
    
    private var filteredDestinations: [Destination] {
        
        // Checks if the user has Typed
        if searchText.isEmpty {
            
            // Checks if recent destinations is empty
            if recentDestinations.isEmpty {
                
                // Return the list of destinations everything else is true
                return suggestedDestinations
                
            }
            
            // return recents destinations if they exist
            return recentDestinations
        }
        
        return destinationRecords.filter { destination in
            //ignoring the Case
            destination.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Setting the campus Region as a constant. This sets the map layers dimensions behind on the campus.
    
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
    
    //select destinations function
    private func selectDestination(id: String){
        // Set the selected destination
        selectedMapDestinationID = id
        
        if let destination = destinationRecords.first(where: { destination in
            destination.id == id
        }) {
            // if destination is found then calculate route
            calculateRoute(to: destination)
        } else {
            selectedRoute = nil
        }
        
        //Removing all the appearance of the selected destination in the Array
        recentDestinationIDs.removeAll { recentID in
            recentID == id
        }
        
        //Putting the added location at the front of the the array
        recentDestinationIDs.insert(id, at: 0)
        
        // if the array is greater than 5 remove the last destination searched
        if recentDestinationIDs.count > 5 {
            recentDestinationIDs.removeLast()
        }
        
        // Saving the array to the temporary app storage
        UserDefaults.standard.set(recentDestinationIDs, forKey: "recentDestinationIDs")
        
        //Release the search focus so testfield is not active
        isSearchFocused = false
    }
    
    private func isAmbiguousRouteStart(_ closest: WalkingStartMatch, alternative: WalkingStartMatch?, accuracy: Double) -> Bool {
        guard let alternative, alternative.distanceFromUser <= min(accuracy, 10 ) else {
            return false
        }
        
        let first = CLLocation(
            latitude: closest.coordinate.latitude,
            longitude: closest.coordinate.longitude
        )
        let second = CLLocation(
            latitude: alternative.coordinate.latitude,
            longitude: alternative.coordinate.longitude
        )
        
        return first.distance(from: second) >= 2
    }
    // Gets the route from a start location
    private func routeFromStart( _ startMatch: WalkingStartMatch, to destination: Destination, temporaryStartID: String) -> (edges: [WalkingEdge], distance: Double)? {
        
        var routingGraph = walkingGraph
        let edge = startMatch.edge
        let fraction = startMatch.fractionAlongEdge
        
        // Connect the matched point to both ends of the walkway.
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
            )]
        let candidateNodeIDs = destination.arrivalNodeID.map { [$0] } ?? destination.arrivalCandidateNodeIDs
        let router = WalkingRouter()
        var bestRoute: (edges: [WalkingEdge], distance: Double)?
        
        for nodeID in candidateNodeIDs {
            guard let edges = router.findRoute(
                from: temporaryStartID,
                to: nodeID,
                in: routingGraph
            ) else {
                continue
            }

            let distance = edges.reduce(0.0) { $0 + $1.distanceMeters }

            if distance < (bestRoute?.distance ?? .infinity) {
                bestRoute = (edges: edges, distance: distance)
            }
        }
        return bestRoute
    }
    
    private func pointNearRouteStart(_ edges: [WalkingEdge], from start: CLLocationCoordinate2D, at distance: Double) -> CLLocation? {
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
        // For a route shorter than five meters, use its endpoint.
        let endpoint = previous.coordinate
        return CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude)
    }
    
    // Calculates the selected route
    private func calculateRoute(to destination: Destination, isRefresh: Bool = false) {
        
        if !isRefresh {
            // set the selectedRoute to Null
            selectedRoute = nil
            selectedRouteDistance = nil
            lastRouteCalculationLocation = nil
        }
        
        routeMessage = nil
        
        //Getting the user User's current location
        guard let location = locationManger.currentLocation else {
            // setting the route message if unavailable
            showRouteFailure(
                "Your location is unavailable. Check Location access and wait for a reading",
                isRefresh: isRefresh
            )
            
            return
        }
        
        
        let age = Date().timeIntervalSince(location.timestamp)
        
        guard location.horizontalAccuracy >= 0, age >= -5, age <= 15 else {
            // setting the route message if location to old
            showRouteFailure(
                "Waiting for a recent, valid location. Try selecting your destination again shortly.",
                isRefresh: isRefresh
            )
            return
        }
        guard location.horizontalAccuracy <= 10 else {
            // setting the route message if location uncertain
            showRouteFailure(
                "Your location is too uncertain to choose a walking path. Move to an open area and try again.",
                isRefresh: isRefresh
            )
            
            return
        }
        
        // Loads our walking start mathcer
        let matcher = WalkingStartMatcher()
        
        // creates a variable that stores the nearest match
        var nearestMatch: WalkingStartMatch?
        var alternativeMatch: WalkingStartMatch?
        var seenSegments = Set<[String]>()
        
        for edges in walkingGraph.values {
            for edge in edges {
                let segmentKey = [edge.fromNodeID, edge.toNodeID].sorted()
                guard seenSegments.insert(segmentKey).inserted else {
                    continue
                }
                guard let match = matcher.match(location: location, to: edge, coordinates: walkingNodeCoordinates) else {
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
        
        
        // set Starting point to nearest amtch
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
        nearestNodeIDs = startMatch.edge.wayID
        nearestDistances = startMatch.distanceFromUser
        
        if let result = routeFromStart(startMatch, to: destination, temporaryStartID: temporaryStartID
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
               ) {
                let separation = primaryPoint.distance(from: alternativePoint)
                // A noticeable difference in the opening guidance may need confirmation.
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
                    
                    if !endpoints.isEmpty,endpoints.count == alternativeRoute.edges.count {
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
    
    private func showRouteFailure(_ message: String, isRefresh: Bool) {
        if isRefresh && selectedRoute != nil {
            routeMessage = "\(message)\nShowing the previous route preview; its starting point, distance, and time have not been updated."
        } else {
            routeMessage = message
        }
    }
    
    private var selectedRouteDistanceText: String? {
        guard let meters = selectedRouteDistance else {
            return nil
        }
        
        let miles = meters/1609.344
        
        if miles < 0.1 {
            let feet = meters/0.3048
            let roundedFeet = (feet / 10).rounded() * 10
            
            return String(format: "%.0f ft", roundedFeet)
        }
        
        return String(format: "%.1f mi", miles)
    }
    
    // constant walking speed
    private let walkingSpeedMetersPerSecond: Double = 1.4
    
    // Estimated walking time in seconds
    private var estimatedWalkingTimeSeconds: Double? {
        guard let distance = selectedRouteDistance else {
            return nil
        }
        
        return distance / walkingSpeedMetersPerSecond
    }
    
    private var selectedRouteCoordinates: [CLLocationCoordinate2D] {
        // if we can get the route then store the first edge
        guard let route = selectedRoute,
              let firstEdge = route.first else {
            return []
        }
        
        // Stores the to node ids that have been selected starting with the first from Node ID
        var nodeIDs = [firstEdge.fromNodeID]
        //for each edge store were it goes to
        for edge in route {
            nodeIDs.append(edge.toNodeID)
        }
        // stores the coordinates
        var coordinates: [CLLocationCoordinate2D] = []
        // for each node ID  get its coordinate and store it
        for nodeID in nodeIDs {
            guard let coordinate = walkingNodeCoordinates[nodeID] else {
                return []
            }
            
            coordinates.append(coordinate)
        }
        return coordinates
    }
    
    
    
    private func recalculateActiveRoute(to destination: Destination) -> Bool {
        
        calculateRoute(to: destination, isRefresh: true)
        let coordinates = selectedRouteCoordinates
        
        guard routeMessage == nil,
              let routeLocation = lastRouteCalculationLocation,
              coordinates.count >= 2 else {
            return false
        }
        
        arStartLocation = routeLocation
        arRouteCoordinates = coordinates
        activeRouteStartDiagnostic = latestRouteStartDiagnostic
        arRerouteMessage = "Route recalculated to \(destination.name)."
        arRouteSessionID = UUID()
        return true
    }
    
    @MainActor
    private func startNavigation(to destination: Destination) async {
        let granted = await cameraPermissionManager.requestPermission()
        
        guard granted else {
            cameraPermissionMessage = "Camera access is unavailable. Check ArNav’s camera permission in Settings."
            return
        }
        
        cameraPermissionMessage = nil
        
        //Recalculate before entering AR
        calculateRoute(to: destination)
        
        guard selectedRoute != nil,
                let routeLocation = lastRouteCalculationLocation else {
            return
        }
        
        //Save the location used for this route calculation
        arStartLocation = routeLocation
        arRouteCoordinates = selectedRouteCoordinates
        pendingAlternateStartCoordinates = alternateStartCoordinates
        activeRouteStartDiagnostic = latestRouteStartDiagnostic
        arRerouteMessage = nil
        if routeStartNeedsConfirmation {
            isShowingStartConfirmation = true
        } else {
            isShowingARNavigarion = true
        }
        
    }
    
    var body: some View {
        
        //Allows us to stack different elements on top of each other
        ZStack(alignment: .top){
            
            // Creates the map layer that appears on the screen from the region set
            Map(initialPosition: .region(campusRegion),
                selection: $selectedMapDestinationID
            ) {
                if selectedRouteCoordinates.count >= 2 {
                    // Draw a line draws from each selected route coordinate
                    MapPolyline(coordinates: selectedRouteCoordinates)
                        .stroke(.blue, lineWidth: 5)
                }
                UserAnnotation {
                    ZStack {
                        if let heading = locationManger.headingDegrees {
                            // draw the cone changing the size dependong on accuracy
                            HeadingCone(halfAngle: locationManger.headingHalfAngle)
                            // set the color to blue and reduce the opacity
                                .fill(.blue.opacity(0.3))
                            //rotating the map to the right location ignoring the roatiton of the map
                                .rotationEffect(.degrees(heading - mapHeading))
                        }
                        // user icon
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
                
                // for each destination records make a marker
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
                // on the change of the marker
                .onChange(of: selectedMapDestinationID) { _, newID in
                    // if you csn get the destination record were the marker id matches then select the destination
                    if let id = newID{
                        selectDestination(id: id)
                    }
                    
                    
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    mapHeading = context.camera.heading
                }
            
            if locationManger.authorizationStatus == .notDetermined {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("Enable my location") {
                            locationManger.requestPermission()
                        }
                        .padding(10)
                        .background(.background ,in: RoundedRectangle(cornerRadius: 12))
                        
                        Spacer()
                    }
                    Spacer()
                }
                
            } else if locationManger.authorizationStatus == .denied {
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Text("Location access is off. You can still browse destinations. Enable Location access in Settings to use your current location.")
                            .font(.footnote)
                            .padding(10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                
            } else if locationManger.authorizationStatus == .restricted {
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Text("Location access is restricted on this device. You can still browse destinations.")
                            .font(.footnote)
                            .padding(10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                
                
            }
        
            
            
            VStack(spacing: 2) {
                
                // TextBox where the user types and results only appears when field is focused
                TextField("Search destinations", text: $searchText)
                    .focused($isSearchFocused)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .background(Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                
               /*
                if let location = locationManger.currentLocation {
                    Text("Location Accuracy: \(location.horizontalAccuracy, specifier: "%.1f") meters")
                } else {
                    Text("Waiting")
                }
                */
                if let message = routeMessage {
                    Text(message)
                        .font(.footnote)
                        .padding(10)
                        .background(
                            .background,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                
                // This section only shows when text field is active.
                if (isSearchFocused){
                    
                    // This is the whole Search Bar
                    List {
                         
                        
                        // This section only shows when text field is active.
                        
                        // Text above results providing Context for the user
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
                        
                        // If Filter destinations is empty then say no results
                        if filteredDestinations.isEmpty {
                            Text("No Location Found")
                                .listRowBackground(Color.clear)
                        }
                        
                        
                        // Displaying each destination as selectable button
                        ForEach(filteredDestinations) { destination in
                            
                            Button(destination.name){
                                selectDestination(id: destination.id)
    
                            }
                            .listRowBackground(Color.clear)
                        }
                        
                        
                    }
                    //This hides the black Background
                    .scrollContentBackground(.hidden)
                    
                    //This reduces the top margin of the scroll to zero
                    .contentMargins(.top, 0, for: .scrollContent)
                    
                    // Setting the frame height
                    .frame(height: 300)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .background(Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
                    //clips shapes since it makes a larger shape
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                }
                
            }
            //  Selected destincation card
            VStack {
                // Pushes the section to the bottom
                Spacer()
                // IF destination is selected
                if let destination = selectedDestination {
                    VStack(alignment: .leading, spacing: 8) {
                        // Location name
                        Text(destination.name)
                            .font(.title2)
                            .bold()
                        HStack {
                            Spacer()
                            // Distance to location
                            if let distanceText = selectedRouteDistanceText {
                                Text(distanceText)
                                    .padding(.bottom, 10)
                            }
                        }
                        HStack {
                            // Time to the the location
                            if let seconds = estimatedWalkingTimeSeconds {
                                Text("Estimated walk: \(seconds / 60, specifier: "%.1f") minutes")
                            }
                            
                            Spacer()
                            
                            Button {
                                // Makes the request run asynchronously
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
                    .background(Color(red: 0.25, green: 0.60, blue: 0.73).opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            
        }
        // on the load of the vStack
        .onAppear {
            
            
            //This checks if the file is stored in the application bundle
            if let fileURL = Bundle.main.url(
                forResource: "Campus-map",
                withExtension: "osm"
            ) {
                //the file was found
                print("Campus map found:", fileURL)
                
                //Creating a loader to be the parser's delegate
                let loader = OSMDestinationLoader()
                
                // Creating a parser
                if let parser = XMLParser(contentsOf: fileURL) {
                    // Sets the loader as Delegate meaning the XML notifications are sent to the loader
                    parser.delegate = loader
                    
                    // This begins the read and returns true if parsing is possible
                    if parser.parse() {
                        
                        //fill the destination record with the destinations read from the Open street XML file
                        destinationRecords = loader.destinations
                        
                        // fill the suggested destinations to 5 random ids
                        if suggestedDestinationIDs.isEmpty {
                            suggestedDestinationIDs = destinationRecords
                                .shuffled()
                                .prefix(5)
                                .map { destination in
                                    destination.id
                                }
                        }
                        
                        // Storing all footpaths and the service path not to MCGaw chapel
                        let walkingWays = loader.ways.filter { way in
                            way.tags["highway"] == "footway" ||
                            way.id == "297425916"
                        }

                       // print("Walking-network candidates:", walkingWays.count)
                        
                        var walkingEdges: [WalkingEdge] = []
                        
                        for way in walkingWays {
                            
                            for (fromID, toID) in zip( way.nodeIDs, way.nodeIDs.dropFirst()) {
                                
                                if let fromCoordinate = loader.nodeCoordinates[fromID],
                                   let toCoordinate = loader.nodeCoordinates[toID] {
                                    
                                    let fromLocation = CLLocation( latitude: fromCoordinate.latitude, longitude: fromCoordinate.longitude)
                                    let toLocation = CLLocation(latitude: toCoordinate.latitude, longitude: toCoordinate.longitude)
                                    
                                    let distanceMeters = fromLocation.distance(from: toLocation)
                                    
                                    let edge = WalkingEdge(wayID: way.id, fromNodeID: fromID, toNodeID: toID, distanceMeters: distanceMeters)
                                
                                    walkingEdges.append(edge)
                                    
                                    let reverseEdge = WalkingEdge(wayID: way.id, fromNodeID: toID, toNodeID: fromID, distanceMeters: distanceMeters)
                                    
                                    walkingEdges.append(reverseEdge)
                                    
                                    
                                    
                                } else {
                                    print("Missing coordinate for: ", fromID, toID)
                                }
                            }
                        }
                        
                
                        
                        print("Stores walking edges: ", walkingEdges.count)
                        
                        //Soring where to got to next from all connections
                        let adjacency = Dictionary(grouping: walkingEdges, by: {edge in edge.fromNodeID})
                        
                        // Stores the connection in walking graph
                        walkingGraph = adjacency
                        // stored to help know where to draw nodes on the map
                        walkingNodeCoordinates = loader.nodeCoordinates
                        
                        for way in loader.ways {
                            if way.tags["building"] != nil {

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
                        
                        
                        
                        
                    }else {
                        // The parse failed and it prints the error
                        print("XML parsing failed: ", parser.parserError?.localizedDescription ?? "Unkown error")
                    }
                }else {
                    // Could not create the XML parser
                    print("Could not create the XML parser")
                }
            } else {
                // The file could not be found
                print("Campus map file not found")
            }
        }
        // when the scene changes
        .onChange(of: scenePhase) { _, newPhase in
            // if the screen is active update location
            if newPhase == .active {
                locationManger.startUpdates()
            } else {
                locationManger.stopUpdates()
            }
        }
        // When the location changes
        .onChange(of: locationManger.currentLocation) {_, newLocation in
            // get the location and selected destination
            guard let location = newLocation,
                  let destination = selectedDestination else {
                return
            }
            
            // if we have the previous location
            if let previousLocation = lastRouteCalculationLocation {
                // get the distance moves
                let distanceMoved = location.distance(from: previousLocation)
                
                // if the distance moved is less than 5 return
                guard distanceMoved >= 5 else {
                    return
                }
            }
            
            // calculate route
            calculateRoute(to: destination, isRefresh: true)
        }
        .sheet(
            isPresented: $isShowingStartConfirmation,
            onDismiss: {
                pendingAlternateStartCoordinates = []

                if shouldOpenARAfterStartReview {
                    shouldOpenARAfterStartReview = false
                    isShowingARNavigarion = true
                }
            }
        ) {
            NavigationStack {
                let hasAlternateStart = pendingAlternateStartCoordinates.count >= 2
                Map(initialPosition: .automatic) {
                    UserAnnotation()

                    if arRouteCoordinates.count >= 2 {
                        MapPolyline(coordinates: arRouteCoordinates)
                            .stroke(.blue, lineWidth: 6)

                        if let start = arRouteCoordinates.first {
                            Marker("Suggested start", coordinate: start)
                                .tint(.blue)
                        }
                    }

                    if hasAlternateStart {
                        MapPolyline(coordinates: pendingAlternateStartCoordinates)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))

                        if let start = pendingAlternateStartCoordinates.first {
                            Marker("Other start", coordinate: start)
                                .tint(.orange)
                        }
                    }
                }
                .navigationTitle("Choose your starting path")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Text("Choose the route that starts on your walkway.")
                            .font(.subheadline)

                        Button("Use Suggested Start") {
                            shouldOpenARAfterStartReview = true
                            isShowingStartConfirmation = false
                        }
                        .buttonStyle(.borderedProminent)

                        if hasAlternateStart {
                            Button("Use Other Start") {
                                arRouteCoordinates = pendingAlternateStartCoordinates
                                activeRouteStartDiagnostic = "Other start selected on the map."
                                shouldOpenARAfterStartReview = true
                                isShowingStartConfirmation = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingStartConfirmation = false
                        }
                    }
                }
            }
        }
        // changes screen when ar navigation is true
        .fullScreenCover(isPresented: $isShowingARNavigarion) {
            if let destination = selectedDestination, let location = arStartLocation {
                ARNavigationView(destinationName: destination.name, routeCoordinates: arRouteCoordinates, startLocation: location, locationManger: locationManger, rerouteMessage: arRerouteMessage, routeStartDiagnostic: activeRouteStartDiagnostic, onReroute: {recalculateActiveRoute(to: destination)})
                    .id(arRouteSessionID)
            }
        }
        
    }
}


#Preview {
    ContentView()
    
}
