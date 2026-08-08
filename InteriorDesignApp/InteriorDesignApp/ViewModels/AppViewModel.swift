import Foundation

enum AppRoute: Equatable {
    case home
    case captureMethod
    case videoCapture
    case videoReview
    case upload
    case processing
    case viewer
    case roomPlanCapture
    case roomPlanEditor
    case roomPlanAR
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var route: AppRoute = .home
    @Published var processingViewModel: ProcessingViewModel?
    @Published var viewerViewModel: RoomViewerViewModel?
    @Published var videoCaptureViewModel: RoomVideoCaptureViewModel?
    @Published var videoReviewViewModel: VideoReviewViewModel?
    @Published var roomPlanCaptureViewModel: RoomPlanCaptureViewModel?
    @Published var editableRoomPlanViewModel: EditableRoomPlanViewModel?
    @Published private(set) var hasSavedRoomPlanProject = false

    let homeViewModel = HomeViewModel()
    let uploadViewModel = UploadViewModel()
    let captureMethodViewModel = CaptureMethodViewModel()

    private let designService: RoomDesignProviding
    private let roomScanService: RoomScanSubmitting
    private let roomPlanPersistence: RoomPlanProjectPersisting

    init(
        designService: RoomDesignProviding,
        roomScanService: RoomScanSubmitting
    ) {
        self.designService = designService
        self.roomScanService = roomScanService
        self.roomPlanPersistence = RoomPlanPersistenceService()
        self.hasSavedRoomPlanProject = (try? roomPlanPersistence.loadMostRecent()) != nil
        AppDebugLog.write("AppViewModel initialized")
    }

    func showHome() {
        processingViewModel?.cancel()
        videoCaptureViewModel?.stopSession()
        route = .home
    }

    func showCaptureMethods() {
        processingViewModel?.cancel()
        videoCaptureViewModel?.stopSession()
        route = .captureMethod
    }

    func showVideoCapture() {
        videoCaptureViewModel?.stopSession()
        videoCaptureViewModel = RoomVideoCaptureViewModel()
        route = .videoCapture
    }

    func showRoomPlanCapture() {
        roomPlanCaptureViewModel = RoomPlanCaptureViewModel { [weak self] project in
            self?.showRoomPlanEditor(project)
        }
        route = .roomPlanCapture
    }

    func showRoomPlanEditor(_ project: RoomPlanProject) {
        editableRoomPlanViewModel = EditableRoomPlanViewModel(
            project: project,
            persistence: roomPlanPersistence
        )
        hasSavedRoomPlanProject = true
        route = .roomPlanEditor
    }

    func openSavedRoomPlanProject() {
        do {
            guard let project = try roomPlanPersistence.loadMostRecent() else { return }
            showRoomPlanEditor(project)
        } catch {
            AppDebugLog.write("Could not load saved RoomPlan project: \(error.localizedDescription)")
        }
    }

    func showRoomPlanAR() {
        guard editableRoomPlanViewModel != nil else { return }
        route = .roomPlanAR
    }

    func returnToRoomPlanEditor() {
        guard editableRoomPlanViewModel != nil else { return }
        route = .roomPlanEditor
    }

    func showVideoReview(_ video: RoomScanVideo) {
        videoCaptureViewModel?.stopSession()
        videoReviewViewModel = VideoReviewViewModel(video: video)
        route = .videoReview
    }

    func retakeVideo() {
        videoReviewViewModel = nil
        showVideoCapture()
    }

    func showUpload() {
        processingViewModel?.cancel()
        route = .upload
    }

    func beginProcessing() {
        guard
            let room = uploadViewModel.selectedRoom,
            let selectedPhoto = uploadViewModel.selectedPhoto
        else { return }
        processingViewModel = ProcessingViewModel(
            room: room,
            selectedPhoto: selectedPhoto,
            designService: designService
        )
        route = .processing
    }

    func beginVideoProcessing(_ video: RoomScanVideo) {
        guard let room = uploadViewModel.selectedRoom ?? SampleData.rooms.first else { return }
        processingViewModel = ProcessingViewModel(
            room: room,
            roomScanVideo: video,
            roomScanService: roomScanService
        )
        route = .processing
    }

    func cancelProcessing() {
        let wasVideoProcessing = processingViewModel?.isVideoProcessing == true
        processingViewModel?.cancel()
        route = wasVideoProcessing ? .videoReview : .upload
    }

    func openDefaultSampleScene() {
        guard let room = SampleData.rooms.first else { return }
        openSampleScene(room)
    }

    func openSampleScene(_ room: SampleRoom) {
        uploadViewModel.select(room)
        let scene = SampleData.scene(for: room)
        AppDebugLog.write(
            "Created sample scene id=\(scene.id) furniture=\(scene.furniture.count)"
        )
        viewerViewModel = RoomViewerViewModel(scene: scene)
        route = .viewer
    }

    func showViewer(_ scene: RoomScene) {
        AppDebugLog.write(
            "Opening generated scene id=\(scene.id) furniture=\(scene.furniture.count)"
        )
        viewerViewModel = RoomViewerViewModel(scene: scene)
        route = .viewer
    }
}
