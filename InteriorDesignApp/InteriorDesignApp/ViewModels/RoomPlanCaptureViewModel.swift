import AVFoundation
import ARKit
import Foundation
import RoomPlan

enum RoomPlanCaptureState: Equatable {
    case preparing
    case scanning
    case processing
    case unsupported
    case permissionDenied
    case failed(String)
}

@MainActor
final class RoomPlanCaptureViewModel: ObservableObject {
    @Published private(set) var state: RoomPlanCaptureState = .preparing
    @Published private(set) var finishRequest = 0
    @Published private(set) var cancelRequest = 0

    let onCompleted: (RoomPlanProject) -> Void

    init(onCompleted: @escaping (RoomPlanProject) -> Void) {
        self.onCompleted = onCompleted
    }

    var isFinishEnabled: Bool { state == .scanning }

    func prepare() async {
        guard RoomCaptureSession.isSupported else {
            state = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .scanning
        case .notDetermined:
            state = await AVCaptureDevice.requestAccess(for: .video) ? .scanning : .permissionDenied
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .failed("Camera access could not be determined.")
        }
    }

    func finish() {
        guard state == .scanning else { return }
        finishRequest += 1
        state = .processing
    }

    func cancel() {
        cancelRequest += 1
    }

    func processingDidBegin() {
        state = .processing
    }

    func didCapture(_ room: CapturedRoom, worldMap: ARWorldMap?) {
        let archivedWorldMap: Data?
        if let worldMap {
            archivedWorldMap = try? NSKeyedArchiver.archivedData(
                withRootObject: worldMap,
                requiringSecureCoding: true
            )
        } else {
            archivedWorldMap = nil
        }
        let project = RoomPlanProject(
            capturedRoom: room,
            archivedWorldMap: archivedWorldMap
        )
        AppDebugLog.write(
            "RoomPlan completed; walls=\(project.walls.count) doors=\(project.doors.count) windows=\(project.windows.count) openings=\(project.openings.count) objects=\(project.objects.count)"
        )
        for category in Set(project.objects.map(\.category)).sorted() {
            AppDebugLog.write("RoomPlan recognized category=\(category)")
        }
        onCompleted(project)
    }

    func didFail(_ error: Error?) {
        state = .failed(error?.localizedDescription ?? "RoomPlan could not process this room.")
    }
}
