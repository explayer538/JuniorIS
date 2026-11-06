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
    
    //Variable that stores recently clicked locations
    private var recentDestinations: [Destination] {
        recentDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }
    
    // Recent destination IDs that makes an Array if the is saved data for the key
    // if not intializes an empty array
    @State private var recentDestinationIDs: [String] = UserDefaults.standard.stringArray(forKey: "recentDestinationIDs") ?? []
    
    //Text Field Tracking state
    @FocusState private var isSearchFocused: Bool
    
    // An array which stores the randomly selected suggested destinations
    private var suggestedDestinations: [Destination] {
        //create an array for Suggest IDs that match the destinations id
        suggestedDestinationIDs.compactMap { id in
            destinationRecords.first { destination in
                destination.id == id
            }
        }
    }
    
    // An Array which stores the IDs of the suggested Destinations
    @State private var suggestedDestinationIDs: [String] = []
    
    
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
    
    // Walking graph for selected destination
    @State private var walkingGraph: [String: [WalkingEdge]] = [:]
    // Stores the selected route
    @State private var selectedRoute: [WalkingEdge]? = nil
    // Walking node coordinates
    @State private var walkingNodeCoordinates: [String: CLLocationCoordinate2D] = [:]
    
   
    
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
    
    @State private var mapHeading: Double = 0
    @State private var lastRouteCalculationLocation: CLLocation? = nil
    
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
        var nearestMatch: WalkingStartMatch? = nil
        
        // For each edge in the array of outgoing edges
        for edges in walkingGraph.values {
            // for each edge segment in the edge
            for edge in edges {
                
                //Storing the matched point
                guard let match = matcher.match(location: location, to: edge, coordinates: walkingNodeCoordinates) else {
                    continue
                }
                
                // if the neareast match distance from user exists then set as best ditance
                let bestDistance = nearestMatch?.distanceFromUser ?? Double.infinity
                
                // If the match distance is less than the best distance
                if match.distanceFromUser < bestDistance {
                    nearestMatch = match
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
        
        // A copy of the walking graph to modify without affecting the actual network
        var routingGraph = walkingGraph
        // the new starting node we would add to the network
        let temporaryStartID = "temporary-user-start"
        
        //stores the matched edge
        let matchedEdge = startMatch.edge
        //stores the fraction of the user along the edge
        let fraction = startMatch.fractionAlongEdge
        
        // distance to start od edge from user
        let distanceToFrom = fraction * matchedEdge.distanceMeters
        // distance to end to edge from user
        let distanceToTo = (1-fraction) * matchedEdge.distanceMeters
        
        // add edges to the network
        routingGraph[temporaryStartID] = [
            WalkingEdge(wayID: matchedEdge.wayID, fromNodeID: temporaryStartID, toNodeID: matchedEdge.fromNodeID, distanceMeters: distanceToFrom),
            WalkingEdge(wayID: matchedEdge.wayID, fromNodeID: temporaryStartID, toNodeID: matchedEdge.toNodeID, distanceMeters: distanceToTo)
        ]
        
        // Store the coordinate in the global coordnate dict
        
        nearestNodeIDs = startMatch.edge.wayID
        nearestDistances = startMatch.distanceFromUser
        
       
        //Intializes the router
        let router = WalkingRouter()
        //Stores the nodes that connect the oath and building
        let candidateNodeIDs: [String]
        // if the destination has an arrival node then we put that in candidateNodes
        //else not we put the array of nodes that relate to the building and path
        if let arrivalNodeID = destination.arrivalNodeID {
            candidateNodeIDs = [arrivalNodeID]
        } else {
            candidateNodeIDs = destination.arrivalCandidateNodeIDs
        }
        
        // set shortest distance to infinity
        var shortestDistance = Double.infinity
        
        var foundNewRoute = false
        
        // Now for each of the candidate nodes we would find the one that gives us the shortest distance
        for nodeID in candidateNodeIDs {
            guard let route = router.findRoute(from: temporaryStartID, to: nodeID, in: routingGraph) else {
                continue
            }
            
            var routeDistance = 0.0
            
            for edge in route {
                routeDistance += edge.distanceMeters
            }
            
            if routeDistance < shortestDistance {
                shortestDistance = routeDistance
                selectedRoute = route
                selectedRouteDistance = routeDistance
                foundNewRoute = true
                
                
            }
        }
        
        if foundNewRoute {
            walkingNodeCoordinates[temporaryStartID] = startMatch.coordinate
            lastRouteCalculationLocation = location
            print("Selected route distance: ", shortestDistance, "meters")
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
    // object that requests camera permission
    @State private var cameraPermissionManager = CameraPermissionManager()
    // holds feedback when camera access is not available
    @State private var cameraPermissionMessage: String? = nil
    
    @State private var isShowingARNavigarion = false
    
    @State private var arStartLocation: CLLocation? = nil
    
    var body: some View {
        
        //Allows us to stack different elements on top of each other
        ZStack(alignment: .top){
            
            // Creates the map layer that appears on the screen from the region set
            Map(initialPosition: .region(campusRegion),
                selection: $selectedMapDestinationID
            ) {
                // If we have enough coordinates
                if selectedRouteCoordinates.count >= 2 {
                    // Draw a line draws from each selected route coordinate
                    MapPolyline(coordinates: selectedRouteCoordinates)
                        .stroke(.blue, lineWidth: 5)
                }
                UserAnnotation {
                    ZStack {
                        // if we can get the heading
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
                                    let granted = await cameraPermissionManager.requestPermission()
                                    
                                    if granted {
                                        cameraPermissionMessage = nil
                                        guard let location = locationManger.currentLocation else {
                                            routeMessage = "Waiting for your locaion. Try to Start again"
                                            return
                                        }
                                        let age = Date().timeIntervalSince(location.timestamp)
                                        
                                        guard location.horizontalAccuracy >= 0, age >= -5, age <= 15 else {
                                            routeMessage = "A recent, accurate location is needed to start AR. Try again shortly."
                                            return
                                        }
                                        
                                        arStartLocation = location
                                        isShowingARNavigarion = true
                                    } else {
                                        cameraPermissionMessage = "Camera access is unavailable. Check ArNav’s camera permission in Settings."
                                    }
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
        // changes screen when ar navigation is true
        .fullScreenCover(isPresented: $isShowingARNavigarion) {
            if let destination = selectedDestination, let location = arStartLocation {
                ARNavigationView(destinationName: destination.name, routeCoordinates: selectedRouteCoordinates, startLocation: location)
            }
        }
        
    }
}


#Preview {
    ContentView()
    
}
