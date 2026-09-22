# AR Campus Navigation

An iPhone application that helps pedestrians navigate a college campus by displaying a short augmented reality (AR) route through the camera view.

## Research question

How does augmented reality navigation affect pedestrian navigation efficiency and cognitive workload compared with Google Maps on a college campus?

## Project goals

- Let users find campus buildings and calculate walking routes.
- Display nearby route guidance in AR and update it as the user moves.
- Recalculate guidance after route deviations and provide a conventional map fallback when AR tracking is unreliable.
- Compare navigation performance and perceived workload with Google Maps.

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
