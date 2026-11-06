//
//  CameraPermissionManager.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 11/3/26.
//

// Apple camera access API
import AVFoundation
import Observation

@Observable

class CameraPermissionManager {
    // Stores the Camera authorization status
    private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    @MainActor
    // function to requestion camera permsion and it waits for a response
    func requestPermission() async -> Bool {
        // stores the request response after waiting without freezing intefrace
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        
        // Sets the authorization Status
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        return granted
    }
}
