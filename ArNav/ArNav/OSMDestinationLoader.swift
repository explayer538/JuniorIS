import CoreLocation
import Foundation

/// Collects OSM geometry and named destinations for the local routing graph.
class OSMDestinationLoader: NSObject, XMLParserDelegate {

    private(set) var destinations: [Destination] = []

    private(set) var nodeCoordinates: [String: CLLocationCoordinate2D] = [:]

    private var currentNodeID: String? = nil

    private var currentNodeTags: [String: String] = [:]

    private var currentWayID: String? = nil

    private var currentWayNodeIDs: [String] = []

    private var currentWayTags: [String: String] = [:]

    private(set) var ways: [OSMWay] = []

    private(set) var nodeCount = 0

    private(set) var nodeTags: [String: [String: String]] = [:]

    /// Collects node, way, and tag attributes as XML elements begin.
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]

    ) {
        // Keep node and way tag state separate because tags belong to the currently open element.
        if elementName == "node" {
            nodeCount += 1

            currentNodeID = attributeDict["id"]
            currentNodeTags = [:]

            if let id = attributeDict["id"],
                let latitudeText = attributeDict["lat"],
                let longitudeText = attributeDict["lon"],
                let latitude = Double(latitudeText),
                let longitude = Double(longitudeText)
            {

                nodeCoordinates[id] = CLLocationCoordinate2D(
                    latitude: latitude, longitude: longitude
                )
            }
        } else if elementName == "way" {
            currentWayID = attributeDict["id"]
            currentWayNodeIDs = []
            currentWayTags = [:]
        } else if elementName == "nd", currentWayID != nil {
            if let reference = attributeDict["ref"] {
                currentWayNodeIDs.append(reference)
            }
        } else if elementName == "tag" {

            if let key = attributeDict["k"],
                let value = attributeDict["v"]
            {

                if currentNodeID != nil {
                    currentNodeTags[key] = value
                } else if currentWayID != nil {
                    currentWayTags[key] = value
                }
            }
        }

    }

    /// Finalizes destinations and clears element state when a node or way ends.
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "node" {

            if let name = currentNodeTags["name"],
                let nodeID = currentNodeID
            {

                if let coordinate = nodeCoordinates[nodeID] {
                    let destination = Destination(
                        id: "osm-node-\(nodeID)",
                        name: name,
                        coordinate: coordinate)

                    destinations.append(destination)
                }

            }
            if let nodeID = currentNodeID {
                nodeTags[nodeID] = currentNodeTags
            }

            currentNodeID = nil
            currentNodeTags = [:]
        } else if elementName == "way" {
            if currentWayTags["building"] != nil,
                let name = currentWayTags["name"]
            {

                var outlineNodeIDs = currentWayNodeIDs

                // Closed OSM outlines repeat the first node; exclude that duplicate from the marker average.
                if outlineNodeIDs.count > 1,
                    outlineNodeIDs.first == outlineNodeIDs.last
                {
                    outlineNodeIDs.removeLast()
                }

                let coordinates = outlineNodeIDs.compactMap { nodeID in
                    nodeCoordinates[nodeID]
                }

                if !coordinates.isEmpty,
                    coordinates.count == outlineNodeIDs.count
                {

                    var latitudeTotal = 0.0
                    var longitudeTotal = 0.0

                    for coordinate in coordinates {
                        latitudeTotal += coordinate.latitude
                        longitudeTotal += coordinate.longitude
                    }

                    // Use the outline average as a building label position; routing uses connected arrival nodes.
                    let markerCoordinate = CLLocationCoordinate2D(
                        latitude: latitudeTotal / Double(coordinates.count),
                        longitude: longitudeTotal / Double(coordinates.count)
                    )

                    if let wayID = currentWayID {
                        let destination = Destination(
                            id: "osm-way-\(wayID)",
                            name: name,
                            coordinate: markerCoordinate
                        )

                        destinations.append(destination)
                    }
                }

            }

            if let wayID = currentWayID {
                let way = OSMWay(id: wayID, nodeIDs: currentWayNodeIDs, tags: currentWayTags)

                ways.append(way)
            }

            currentWayID = nil
            currentWayNodeIDs = []
            currentWayTags = [:]
        }
    }

}
