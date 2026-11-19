/// An OSM way retaining its ordered node references and tags.
struct OSMWay {
    let id: String
    let nodeIDs: [String]
    let tags: [String: String]
}
