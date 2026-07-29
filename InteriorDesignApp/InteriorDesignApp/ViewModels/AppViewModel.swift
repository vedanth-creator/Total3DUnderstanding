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
        viewerViewModel = RoomViewerViewModel(scene: SampleData.scene(for: room))
        route = .viewer
    }

    func showViewer(_ scene: RoomScene) {
        viewerViewModel = RoomViewerViewModel(scene: scene)
        route = .viewer
    }
}

