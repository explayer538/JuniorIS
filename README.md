# AR Campus Navigation

An iPhone application that helps pedestrians navigate a college campus by displaying a short augmented reality (AR) route through the camera view.

## Research question

How does augmented reality navigation affect pedestrian navigation efficiency and cognitive workload compared with Google Maps on a college campus?

## Project goals

- Let users find campus buildings and calculate walking routes.
- Display nearby route guidance in AR and update it as the user moves.
- Recalculate guidance after route deviations and provide a conventional map fallback when AR tracking is unreliable.
- Compare navigation performance and perceived workload with Google Maps.

## Requirements

- A Mac with Xcode and an iOS SDK compatible with the project's iOS 27.0 deployment target. The current development environment uses Xcode 27.2.
- A physical iPhone running iOS 27.0 or later that supports ARKit world tracking, with a working camera and location services. Outdoor AR guidance requires a physical device.
- An Apple account configured in Xcode for development signing.
- Camera access and location access while using the app. Precise Location should be enabled for route matching.
- Access to the mapped campus walkways for meaningful navigation testing. MapKit basemap loading may require an internet connection.

The app uses SwiftUI, MapKit, Core Location, ARKit, RealityKit, and AVFoundation. There are no third-party package dependencies or backend services. Routes are calculated locally from the bundled campus map.

## Build and run

1. Clone this repository and open `ArNav/ArNav.xcodeproj` in Xcode.
2. Select the **ArNav** scheme and your connected iPhone as the run destination.
3. Under the **ArNav** target's **Signing & Capabilities**, select your development team and enable automatic signing. If needed, replace the bundle identifier with one available to your team.
4. Trust the development computer and enable Developer Mode on the phone if prompted.
5. Build and run with **Product → Run**. Accept the camera and location requests when using navigation. Previously denied permissions can be changed in the phone's Settings.
6. For testing diagnostics, use the **Debug** configuration. For a demo with Debug-only measurement panels omitted, choose **Product → Scheme → Edit Scheme → Run → Info → Build Configuration → Release**, then run again. Navigation instructions and status messages outside Debug blocks still appear.

## Using the app

1. Enable location, search for a destination or select its map marker, and inspect the route preview.
2. Stand on the intended walkway and tap **Start**. The app recalculates using the latest usable location.
3. If **Choose your starting path** appears, inspect the blue suggested route and dashed orange alternative. Choose the route that begins on your walkway, or cancel to review the campus map.
4. Hold the phone steady with the walkway visible and a gentle downward tilt. Point along your intended route direction for initial automatic alignment. The yellow strip shows the next five meters, including nearby bends. The green marker marks the visible strip's endpoint.
5. Follow the sidewalk. The summary shows estimated distance remaining, walking time, and arrival time using a constant walking speed of 1.4 m/s.
6. If the overlay shifts, stop on a straight section, face along the route, and tap **Align Route**. Automatic walking-direction correction can also run when its tracking, GPS, and movement conditions pass.
7. Open **View Map** from the navigation menu for the active route and heading indicator. **Back to AR** closes the sheet. The map can also open after sustained loss of AR progress and close after sustained recovery when it was opened automatically.
8. If fresh GPS readings consistently indicate a route deviation, the app attempts to recalculate to the same destination. Successful replacement displays **Route recalculated to…** and restarts AR placement.
9. Near the mapped endpoint, **You've arrived** replaces the estimates. Tap **End Navigation** to return to the campus map. The navigation menu also offers **Exit Navigation** at any time.

## Source structure

Application source files are in `ArNav/ArNav/`.

| File | Responsibility |
|---|---|
| `ArNavApp.swift` | App entry point. |
| `ContentView.swift` | Campus map, search, destination selection, graph loading, route calculation, start review, and AR presentation. Also defines `Destination`. |
| `OSMDestinationLoader.swift` | Parses OSM nodes, ways, tags, and named destinations. |
| `OSMWay.swift`, `WalkingEdge.swift` | Map-way and directed walking-edge value types. |
| `WalkingStartMatcher.swift` | Projects a location onto a walking segment. |
| `WalkingRouter.swift` | Finds shortest-distance paths using Dijkstra's algorithm. |
| `LocationManager.swift` | Location authorization, GPS and compass updates, and update lifecycle. |
| `CameraPermissionManager.swift` | Camera permission requests. |
| `ARNavigationView.swift` | Navigation controls, GPS projection, deviation and arrival checks, summary, and fallback presentation. |
| `ARNavigationMapView.swift` | Active route map, heading indicator, destination marker, and return-to-AR control. |
| `RouteStartReviewView.swift` | Map presentation and controls for choosing between captured starting routes. |
| `ARCameraView.swift` | AR session, surface placement, camera projection, route rendering, alignment, and interruption recovery. |
| `LocalRoutePoint.swift` | Converts geographic coordinates into local east/north meters and AR offsets. |
| `HeadingCone.swift` | Heading indicator shared by the maps. |
| `Campus-map.osm` | Bundled map used by the application. |

The route calculator snaps a usable GPS fix to a walking segment, adds a temporary start node, and finds a path to a connected destination endpoint. AR receives a snapshot of that route. Successful deviation rerouting explicitly replaces the snapshot and starts a new AR session.

Only recent destination IDs are persisted in `UserDefaults`. Active routes and navigation progress are held in memory.

## Prototype status and known limitations

The user has demonstrated navigation, arrival and ending a trip, fallback map progress and zoom, and automatic alignment. These observations do not establish accuracy across all campus routes. Deliberate-deviation rerouting and the latest interruption recovery still need dedicated field verification.

- GPS errors can select a neighboring entrance connector or walkway. The start-review check considers two nearby segments and compares their routes at five meters, so it can miss alternatives that diverge and quickly rejoin.
- AR and GPS progress use the closest point across the full route. Crossings and nearby parallel segments can cause jumps in progress, turn timing, or remaining distance.
- Initial and manual alignment depend on the user facing along the correct route. Ground height stays fixed from initial placement, so slopes and tracking changes can displace the overlay.
- Interruption recovery retains the last reliable progress. Moving while the app is interrupted can make that saved position outdated. Recovery may require manual alignment or use of the map.
- Automatic map fallback currently uses progress availability. It may miss an incorrectly placed or invisible strip when progress is still available, and it does not cover every initial placement or unsupported-device failure.
- Some named destinations have no walking-network connection. Arrival endpoints are chosen from connected building-outline nodes and may differ from the intended entrance.
- Arrival can latch from a single qualifying GPS reading near the endpoint.
- The graph includes footways and one selected service road. It does not enforce accessibility, stairs, access restrictions, or all crossing constraints.
- Walking time and arrival are estimates. During a GPS gap, remaining distance holds at the last usable progress.
- No automated test suite is included. The latest Release build was checked with signing disabled, and outdoor behavior is verified through device walks.

## Timeline and time budget

**Proposed start:** September 21, 2026  
**Final deadline:** November 19, 2026  
**Target workload:** approximately 7 hours per week.

| Work category | Planned hours |
|---|---:|
| Core software features | 30.5 |
| Contingency for unexpected problems | 15 |
| **Core software features including contingency** | **45.5** |
| Optional stretch features | 11.5 |
| **Total if every stretch feature is attempted and the full contingency is used** | **57** |

## Development and research schedule

Tasks are listed in calendar order.

| Feature/task | Due date | Notes |
|---|---|---|
| Set up the project and initial campus path data | September 23, 2026 | Confirm the app runs on the iPhone and prepare the small destination/path dataset. |
| [Display selectable campus destinations](https://github.com/explayer538/JuniorIS/issues/1) | September 24, 2026 | 2 hours. Show building names as selectable destinations. |
| [Implement destination search](https://github.com/explayer538/JuniorIS/issues/2) | September 25, 2026 | 2 hours. Filter buildings as the user types. |
| [Request location permission](https://github.com/explayer538/JuniorIS/issues/3) | September 28, 2026 | 1 hour. Request access to the user's location. |
| Check outdoor AR feasibility early | September 30, 2026 | Try a short line on a selected path; identify tracking or alignment blockers before full implementation. |
| [Identify the route starting point](https://github.com/explayer538/JuniorIS/issues/4) | October 1, 2026 | 2 hours. Match the current position to a nearby mapped path. |
| [Calculate a campus walking route](https://github.com/explayer538/JuniorIS/issues/5) | October 5, 2026 | 3 hours. Find an ordered route using estimated walking times. |
| [Display a route preview](https://github.com/explayer538/JuniorIS/issues/6) | October 8, 2026 | 2 hours. Draw the route on a map or report that no route is available. |
| [Add the Start AR Navigation button](https://github.com/explayer538/JuniorIS/issues/7) | October 12, 2026 | 2 hours. Request camera permission and start AR guidance. |
| [Add the End Navigation button](https://github.com/explayer538/JuniorIS/issues/8) | October 13, 2026 | 30 minutes. Stop navigation and guidance. |
| [Implement route alignment calibration](https://github.com/explayer538/JuniorIS/issues/9) | October 16, 2026 | 2 hours. Correct the displayed route's position and direction. |
| [Display the nearby AR route segment](https://github.com/explayer538/JuniorIS/issues/10) | October 19, 2026 | 3 hours. Limit the route line to the upcoming path section. |
| [Update the AR route as the user moves](https://github.com/explayer538/JuniorIS/issues/11) | October 21, 2026 | 2 hours. Advance the line as path segments are completed. |
| [Detect departures from the planned route](https://github.com/explayer538/JuniorIS/issues/12) | October 23, 2026 | 2 hours. Detect when the user leaves the route. |
| [Recalculate the route after a deviation](https://github.com/explayer538/JuniorIS/issues/13) | October 26, 2026 | 3 hours. Generate a new route and refresh guidance. |
| [Provide a map fallback for unreliable AR tracking](https://github.com/explayer538/JuniorIS/issues/14) | October 29, 2026 | 4 hours. Offer a conventional map view. |
| Complete final checks and submission preparation | November 18, 2026 | Use the remaining contingency allowance for fixes, proofreading, bibliography checks, repository cleanup, and a demo rehearsal. |
| Project ready for submission | November 19, 2026 | Final deadline: working prototype, evaluation results, report, and repository ready. Follow the course submission requirements. |

## Stretch goals

These additional features will be considered only after the core tasks are complete and the evaluation and submission schedule is secure. They are optional and have no fixed deadline.

| Feature/task | Due date | Notes |
|---|---|---|
| [Add navigation from inside buildings to outdoors](https://github.com/explayer538/JuniorIS/issues/15) | if time permits | 4 hours. Connect indoor exit directions to the outdoor route. |
| [Add an Avoid Stairs routing option](https://github.com/explayer538/JuniorIS/issues/16) | if time permits | 4 hours. Exclude stairs using recorded path information. |
| [Add spoken turn instructions](https://github.com/explayer538/JuniorIS/issues/17) | if time permits | 1 hour. Read the next-turn guidance aloud. |
| [Add AR line appearance controls](https://github.com/explayer538/JuniorIS/issues/18) | if time permits | 1.5 hours. Let users change the line's color and width. |
| [Let users choose an alternative route](https://github.com/explayer538/JuniorIS/issues/19) | if time permits | 1 hour. Request another route when one exists. |
