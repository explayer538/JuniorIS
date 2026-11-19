/// A directed walking-network connection with its geographic length in meters.
struct WalkingEdge {
    let wayID: String
    let fromNodeID: String
    let toNodeID: String
    let distanceMeters: Double
}
