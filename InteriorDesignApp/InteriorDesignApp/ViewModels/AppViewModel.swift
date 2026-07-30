import Foundation

enum AppRoute: Equatable {
    case home
    case captureMethod
    case videoCapture
    case videoReview
    case upload
    case processing
    case viewer
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var route: AppRoute = .home
    @Published var processingViewModel: ProcessingViewModel?
    @Published var viewerViewModel: RoomViewerViewModel?
    @Published var videoCaptureViewModel: RoomVideoCaptureViewModel?
    @Published var videoReviewViewModel: VideoReviewViewModel?

    let homeViewModel = HomeViewModel()
    let uploadViewModel = UploadViewModel()
    let captureMethodViewModel = CaptureMethodViewModel()

    private let designService: RoomDesignProviding

    init(designService: RoomDesignProviding) {
        self.designService = designService
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
            designService: designService
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
