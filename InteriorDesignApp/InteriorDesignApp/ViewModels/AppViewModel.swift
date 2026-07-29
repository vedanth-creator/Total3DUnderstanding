import Foundation

enum AppRoute: Equatable {
    case home
    case upload
    case processing
    case viewer
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var route: AppRoute = .home
    @Published var processingViewModel: ProcessingViewModel?
    @Published var viewerViewModel: RoomViewerViewModel?

    let homeViewModel = HomeViewModel()
    let uploadViewModel = UploadViewModel()

    private let designService: RoomDesignProviding

    init(designService: RoomDesignProviding) {
        self.designService = designService
        AppDebugLog.write("AppViewModel initialized")
    }

    func showHome() {
        processingViewModel?.cancel()
        route = .home
    }

    func showUpload() {
        processingViewModel?.cancel()
        route = .upload
    }

    func beginProcessing() {
        guard let room = uploadViewModel.selectedRoom else { return }
        processingViewModel = ProcessingViewModel(
            room: room,
            designService: designService
        )
        route = .processing
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
