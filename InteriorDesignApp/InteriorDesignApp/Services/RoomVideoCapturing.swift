import AVFoundation
import Foundation

protocol RoomVideoCapturing: AnyObject {
    var captureSession: AVCaptureSession { get }
    var isSceneLikelyDark: Bool { get }
    var onRecordingFinished: ((Result<RoomScanVideo, Error>) -> Void)? { get set }
    var onInterruptionChanged: ((Bool, String?) -> Void)? { get set }

    func prepare() async throws
    func startRecording() async throws
    func stopRecording()
    func cancelRecording()
    func stopSession()
}

enum RoomVideoCaptureServiceError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed
    case recordingFailed
    case interrupted

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            "Camera access is turned off. Allow access in Settings to record a room scan."
        case .cameraUnavailable:
            "A rear camera is not available on this device."
        case .configurationFailed:
            "The camera could not be prepared. Please try again."
        case .recordingFailed:
            "The room scan could not be recorded."
        case .interrupted:
            "Recording was interrupted by the system."
        }
    }
}
