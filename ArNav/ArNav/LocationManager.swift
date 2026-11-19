import CoreLocation
import Foundation
import Observation

@Observable
/// Publishes usable location and compass updates while permission allows them.
class LocationManager: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private(set) var currentLocation: CLLocation? = nil

    private(set) var currentHeading: CLHeading? = nil

    /// Prefers true north and falls back to magnetic heading when true heading is unavailable.
    var headingDegrees: Double? {
        guard let heading = currentHeading else {
            return nil
        }

        if heading.trueHeading >= 0 {
            return heading.trueHeading
        }

        return heading.magneticHeading
    }

    /// Bounds the cone width so heading uncertainty remains visible on the map.
    var headingHalfAngle: Double {

        guard let heading = currentHeading else {
            return 30
        }

        return min(max(heading.headingAccuracy, 10), 60)

    }

    /// Connects Core Location callbacks to the observable location state.
    override init() {

        super.init()

        manager.delegate = self
    }

    /// Starts or stops sensor updates when authorization changes.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            print("Location permission: not decided yet")

        case .authorizedWhenInUse:
            print("Location permission: allowed while using the app")
            startUpdates()

        case .authorizedAlways:
            print("Location permission: always allowed")
            startUpdates()

        case .denied:
            print("Location permission: denied")
            stopUpdates()
            currentLocation = nil
            currentHeading = nil

        case .restricted:
            print("Location permission: restricted by device settings")
            stopUpdates()
            currentLocation = nil
            currentHeading = nil

        @unknown default:
            print("Location permission: unrecognized status")
        }
    }

    /// Requests location access while the app is in use.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Accepts a recent valid fix for routing and navigation diagnostics.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else {
            return
        }
        guard latestLocation.horizontalAccuracy >= 0 else {
            return
        }

        // Reject stale cached fixes before publishing them; navigation applies its own tighter checks.
        let age = Date().timeIntervalSince(latestLocation.timestamp)

        guard age >= -5 && age <= 15 else {
            return
        }

        currentLocation = latestLocation

        print("Location accuracy: ", latestLocation.horizontalAccuracy, " meters")
        print("Locatio recorded at: ", latestLocation.timestamp)

    }

    /// Reports location service failures for development diagnostics.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Could not get location:", error.localizedDescription)
    }

    /// Discards invalid compass readings before publishing a new heading.
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {

        guard newHeading.headingAccuracy >= 0 else {
            return
        }

        currentHeading = newHeading

    }

    /// Stops location and compass sampling when the scene is inactive.
    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Resumes authorized sensor updates when navigation can use them.
    func startUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }

        manager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

}
