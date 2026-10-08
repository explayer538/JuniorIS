//
//  OSMDestinationLoader.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 10/1/26.
//

//Provides the core XML tools and location Tools
import Foundation
import CoreLocation

//Creating a loader that acts as the Delegate for our XMLParser in ContentView
class OSMDestinationLoader: NSObject, XMLParserDelegate {
    
    //The destionations records
    private(set) var destinations: [Destination] = []
    
    //A dictionary that stores the id associated to the location coordinates.
    private(set) var nodeCoordinates: [String: CLLocationCoordinate2D] = [:]
    
    // Current Node ID
    private var currentNodeID: String? = nil
    
    // The current node Tags
    private var currentNodeTags: [String: String] = [:]
    
    //Id of the current way being read
    private  var currentWayID: String? = nil
    
    //The current ways node references
    private var currentWayNodeIDs: [String] = []
    
    // The current way tags
    private var currentWayTags: [String: String] = [:]
    
    // node count
    private(set) var nodeCount = 0
    
    // A callback XML parser calls when an element starts
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]
    
    ) {
        //checks if the element is a node
        if elementName == "node" {
            // increases the node count
            nodeCount += 1
            
            
            // Setting the node id and and empty tag dictionary
            currentNodeID = attributeDict["id"]
            currentNodeTags = [:]
            
            // the node has an id, latitude, and longitude and stores its coordinates in the dict if it does
            if let id = attributeDict["id"],
               let latitudeText = attributeDict["lat"],
               let longitudeText = attributeDict["lon"],
               let latitude = Double(latitudeText),
               let longitude = Double(longitudeText) {
                
                nodeCoordinates[id] = CLLocationCoordinate2D(
                    latitude: latitude, longitude: longitude
                )
            }
        } else if elementName == "way" {
            //If we see a new way element (Way represents the building outline)
            //Set the currentWay ID
            //Create an empty array of Node references
            //Create a dictionary of the tags and their information
            currentWayID = attributeDict["id"]
            currentWayNodeIDs = []
            currentWayTags = [:]
        } else if elementName == "nd", currentWayID != nil {
            // if we see  a node element
            // and if it has a referneve then we appende the reference
            if let reference = attributeDict["ref"] {
                currentWayNodeIDs.append(reference)
            }
        } else if elementName == "tag" {
            
            if let key = attributeDict["k"],
               let value = attributeDict["v"] {
                
                if currentNodeID != nil {
                    currentNodeTags[key] = value
                } else if currentWayID != nil {
                    currentWayTags[key] = value
                }
            }
        }
        
    }
    
    // A callback XML parser calls when an element ends
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?
    ) {
        // if the ending element is a node
        if elementName == "node" {
            
            // If the current name is set and it has an id
            if let name = currentNodeTags["name"],
               let nodeID = currentNodeID {
            
                print("Named node: ", nodeID, name)
                print("node tags: ", currentNodeTags)
                
                // Get the coordinate using the id
                if let coordinate = nodeCoordinates[nodeID] {
                    // create the destination
                    let destination = Destination (id: "osm-node-\(nodeID)",
                                                   name: name,
                                                   coordinate: coordinate)
                    
                    // add the destination to the records
                    destinations.append(destination)
                }
                
                
                
            }
            
            // set current Node id to null and empty the dictionary
            currentNodeID = nil
            currentNodeTags = [:]
        }
        
        // if the ending element is way
        else if elementName == "way" {
            // Check if the building tag is not null and if it has a name tag
            if currentWayTags["building"] != nil,
               let name = currentWayTags["name"] {
               // print("Named Building: ", name)
                
                // Variable that stores the outlined nodes
                var outlineNodeIDs = currentWayNodeIDs
                
                //This check removes the duplicated nodes
                //Checking if the outlined nodes is greater than one and the first and last nodes are the same which is where they duplications happen
                if outlineNodeIDs.count > 1,
                   outlineNodeIDs.first == outlineNodeIDs.last {
                    // Remove the last node
                    outlineNodeIDs.removeLast()
                }
                
                // Storing the core for all the nodes
                let coordinates = outlineNodeIDs.compactMap{ nodeID in
                    nodeCoordinates[nodeID]
                }
                
                // if the coordinates array is not empty and All outlined nodes were collected
                if !coordinates.isEmpty,
                   coordinates.count == outlineNodeIDs.count {
                    
                    // creat latitude and longitude variables which store the totals
                    var latitudeTotal = 0.0
                    var longitudeTotal = 0.0
                    
                    // Loop through the coordinates and get the totals for the latitude and Lognitude
                    for coordinate in coordinates {
                        latitudeTotal += coordinate.latitude
                        longitudeTotal += coordinate.longitude
                    }
                    
                    // Create an average merker location for the current way you are working on
                    let markerCoordinate = CLLocationCoordinate2D(
                        latitude: latitudeTotal / Double(coordinates.count),
                        longitude: longitudeTotal / Double(coordinates.count)
                    )
                    
                    //print("Approximate Marker: ", markerCoordinate)
                    
                    // if you can set the way id
                    if let wayID = currentWayID {
                        // create a destination variable that holds the destintion Type for the current way with the approximate location.
                        let destination = Destination(
                            id: "osm-way-\(wayID)",
                            name: name,
                            coordinate: markerCoordinate
                        )
                        
                        //Add the destination to the Readable destination Array
                        destinations.append(destination)
                    }
                }
                
                //print("Outline coordinate count: ", coordinates.count)
                //print("Coordinates: ", coordinates)
                
                
            }
            
            // Set the way ID to null
            currentWayID = nil
            //Empty the array of Node Ids
            currentWayNodeIDs = []
            //Empty the tags made
            currentWayTags = [:]
        }
    }

}
