//
//  WalkingRouter.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 10/26/26.
//

struct WalkingRouter {
    
    func findRoute( from startNodeID: String, to destinationNodeID: String, in adjacency: [String: [WalkingEdge]]) -> [WalkingEdge]? {
        
        //Stores the best distance for processed distance
        var distances: [String: Double] = [startNodeID: 0]
        // contains nodes waiting to be processed and their best distance found so far
        var processing: [String: Double] = [startNodeID: 0]
        // remebers how we reached the best node
        var previousEdges: [String: WalkingEdge] = [:]
        
        //Dijkstra Loop for find the shortest paths to nodes
        while let nearest = processing.min(by: {first, second in first.value < second.value}) {
            let currentNodeID = nearest.key
            let currentDistance = nearest.value
            
            processing.removeValue(forKey: currentNodeID)
            
            
            for edge in adjacency[currentNodeID] ?? [] {
                let candidateDistance = currentDistance + edge.distanceMeters
                
                let knownDistance = distances[edge.toNodeID] ?? Double.infinity
                
                if candidateDistance < knownDistance {
                    distances[edge.toNodeID] = candidateDistance
                    previousEdges[edge.toNodeID] = edge
                    processing[edge.toNodeID] = candidateDistance
                }
            }
        }
        
        
        if let distance = distances[destinationNodeID] {
            print("Shortest mapped distance ", distance, "meters")
            // Collects edges used by the route
            var routeEdges: [WalkingEdge] = []
            var tracingNodeID = destinationNodeID
            
            while tracingNodeID != startNodeID {
                guard let edge = previousEdges[tracingNodeID] else {
                    print("Route Connections failed at: ", tracingNodeID)
                    routeEdges.removeAll()
                    break
                }
                
                routeEdges.append(edge)
                tracingNodeID = edge.fromNodeID
            }
            
            if tracingNodeID == startNodeID {
                routeEdges.reverse()
                
                var reconstructedDistance = 0.0

                for edge in routeEdges {
                    reconstructedDistance += edge.distanceMeters
                }
                
                print("Reconstructed distance:", reconstructedDistance, "meters")

                return routeEdges
            }
        } else {
            print("No route found")
            return nil
        }
        return nil
    }
    
}
