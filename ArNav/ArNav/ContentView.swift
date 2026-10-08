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
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct ContentView: View {
    
    //Selected Destination
    @State private var selectedMapDestinationID: String? = nil
    
    // Selected destinations variable that allow a null value
    private var selectedDestination: Destination? {
        destinationRecords.first { $0.id == selectedMapDestinationID}
    }
    
    // Search text variable which manages the filtering results and Text field display
    @State private var searchText: String = ""
    
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
    @State private var recentDestinationIDs: [String] = UserDefaults.standard.stringArray(
                                                        forKey: "recentDestinationIDs") ?? []
    
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
    
    // record of destinations
    @State private var destinationRecords: [Destination] = []
    
    var body: some View {
        
        //Allows us to stack different elements on top of each other
        ZStack(alignment: .top){
            
            // Creates the map layer that appears on the screen from the region set
            Map(initialPosition: .region(campusRegion),
                selection: $selectedMapDestinationID
            ) {
                // for each destination records make a marker
                ForEach(destinationRecords) { record in
                    Marker(record.name, coordinate: record.coordinate)
                        .tag(record.id)
                }
            }
                .onTapGesture {
                    isSearchFocused = false
                    
                }
                // on the change of the marker
                .onChange(of: selectedMapDestinationID) { _, newID in
                    // if you csn get the destination record were the marker id matches then select the destination
                    if let id = newID{
                        selectDestination(id: id)
                    }
                    
                    
                }
        
            
            
            VStack(spacing: 2) {
                
                // TextBox where the user types and results only appears when field is focused
                TextField("Search destinations", text: $searchText)
                    .focused($isSearchFocused)
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                
                // A text that displays the selected destination and tells the user to choose a location if none has been selected.
                
                //Text(selectedDestination ?? "Choose a destination")
                
                Text(selectedDestination?.name ?? "No map marker selected")
                    .padding(8)
                    .background(.background)
                
                // This section only shows when text field is active.
                if (isSearchFocused){
                    
                    // This is the whole Search Bar
                    List {
                         
                        
                        // This section only shows when text field is active.
                        
                        // Text above results providing Context for the user
                        if searchText.isEmpty {
                            if recentDestinations.isEmpty {
                                Text("Suggested destinations")
                            } else {
                                Text("Recent destinations")
                            }
                        } else {
                            Text("Search Results")
                        }
                        
                        // If Filter destinations is empty then say no results
                        if filteredDestinations.isEmpty {
                            Text("No Location Found")
                        }
                        
                        
                        // Displaying each destination as selectable button
                        ForEach(filteredDestinations) { destination in
                            
                            Button(destination.name){
                                selectDestination(id: destination.id)
    
                            }
                        }
                        
                        
                    }
                    //This hides the black Background
                    .scrollContentBackground(.hidden)
                    
                    //This reduces the top margin of the scroll to zero
                    .contentMargins(.top, 0, for: .scrollContent)
                    
                    // Setting the frame height
                    .frame(height: 300)
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
                        print("Suggested IDs: ", suggestedDestinationIDs)
                        print("Suggested Names: ", suggestedDestinations.map {$0.name})
                        
                        /*
                        print("Destination records: ", loader.destinations.count)
                        
                        if let ebert = loader.destinations.first(where: { destination in
                            destination.id == "osm-way-297425911"
                        }) {
                            print("Ebert record: ", ebert.id, ebert.name, ebert.coordinate)
                        }
                        
                        // Printing Count and the amount of stored coordinates
                        print("Node count: ", loader.nodeCount)
                        print("Stored Coordinates: ", loader.nodeCoordinates.count)
                        
                        //A Specfic reference to confirm it's storing the Right values for lowry
                        if let coordinate = loader.nodeCoordinates["3239068661"] {
                            print("Lowry coordinate: ", coordinate.latitude, coordinate.longitude)
                         
                        
                        }
                         */
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
        
    }
}


#Preview {
    ContentView()
    
}
