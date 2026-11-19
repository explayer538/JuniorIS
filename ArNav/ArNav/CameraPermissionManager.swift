import AVFoundation
import Observation

@Observable

/// Exposes camera authorization for entering AR navigation.
class CameraPermissionManager {
    private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    @MainActor
    /// Requests video access and refreshes the displayed authorization state.
    func requestPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)

        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        return granted
    }
}
