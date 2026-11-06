//
//  LocationManager.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 10/11/26.
//

// Make use NSObject class and CLLocation manager
import Foundation
import CoreLocation
import Observation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    
    // Making A CLLocationManger instance to for location information
    private let manager = CLLocationManager()
    
    // Creating a variable to store the authorization status and setting it to not determind intially
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    //Creating a variable to store the user's current location
    private(set) var currentLocation: CLLocation? = nil
    
    // Creating a heading variable the stores where the phone is pointing
    private(set) var currentHeading: CLHeading? = nil
    
    // Picking the heading content view should use
    var headingDegrees: Double? {
        guard let heading = currentHeading else {
            return nil
        }
        
        if heading.trueHeading >= 0 {
            return heading.trueHeading
        }
        
        return heading.magneticHeading
    }
    
    // the computed accurracy of the heading
    var headingHalfAngle: Double {
        
        // if no heading default
        guard let heading = currentHeading else {
            return 30
        }
        
        // return the heading accuracy keeping it at least 10 or at most 60
        return min(max(heading.headingAccuracy, 10), 60)
        
        
    }
    
    override init() {
        
        super.init()
        
        // Letting the location manager send updates to our class
        manager.delegate = self
    }
    
    // A callback function that is called by CLLocationManager
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            print("Location permission: not decided yet")

        case .authorizedWhenInUse:
            print("Location permission: allowed while using the app")
            // Starts Updating Location
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
    
    // Function called to requestion location
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    // Callback fucntion called when the location updates

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // if you are able to get the newest location store it
        guard let latestLocation = locations.last else {
            return
        }
         // if the lastest location's accuracy  is low return
        guard latestLocation.horizontalAccuracy >= 0 else {
            return
        }
        
        // storing the time since that location was recorded
        let age = Date().timeIntervalSince(latestLocation.timestamp)
        
        // maken sure the location is not more than or equal to  15 seconds old
        guard age >= -5 && age <= 15 else {
            return
        }
        
        currentLocation = latestLocation
        
        print("Location accuracy: ", latestLocation.horizontalAccuracy, " meters")
        print("Locatio recorded at: ", latestLocation.timestamp)
        
        //print("Latitude:", latestLocation.coordinate.latitude)
        //print("Longitude:", latestLocation.coordinate.longitude)
    }
    
    
    
    // Callback function when there is an error getting the location
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Could not get location:", error.localizedDescription)
    }
    
    // A funtion that is called when there is a change in the heading
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        
        guard newHeading.headingAccuracy >= 0 else {
            return
        }
        
        currentHeading = newHeading
        
        //print("Magnetic heading: ", newHeading.magneticHeading)
    }
    
    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    
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
