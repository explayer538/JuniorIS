/// Finds shortest-distance routes through the local walking graph.
struct WalkingRouter {

    /// Returns ordered edges to the destination, or nil when no route is reachable.
    func findRoute(
        from startNodeID: String, to destinationNodeID: String, in adjacency: [String: [WalkingEdge]]
    ) -> [WalkingEdge]? {

        var distances: [String: Double] = [startNodeID: 0]
        var processing: [String: Double] = [startNodeID: 0]
        var previousEdges: [String: WalkingEdge] = [:]

        // Process the cheapest pending node first; relax outgoing edges when a shorter path is found.
        while let nearest = processing.min(by: { first, second in first.value < second.value }) {
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
            var routeEdges: [WalkingEdge] = []
            var tracingNodeID = destinationNodeID

            // Trace predecessor edges backward, then reverse them into walking order.
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
