import SwiftUI

enum AnalysisState: Equatable {
    case idle
    case analyzing
    case completed
    case failed(String)
}

struct AnalysisStep: Identifiable, Equatable {
    let id: Int
    let title: String
}

enum ProcessingInput {
    case photo(SelectedPhoto)
    case video(RoomScanVideo)
}

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published private(set) var analysisState: AnalysisState = .idle
    @Published private(set) var analysisProgress = 0.0
    @Published private(set) var completedStepCount = 0

    let room: SampleRoom
    let input: ProcessingInput
    let steps: [AnalysisStep]

    var selectedPhoto: SelectedPhoto? {
        guard case let .photo(photo) = input else { return nil }
        return photo
    }

    var roomScanVideo: RoomScanVideo? {
        guard case let .video(video) = input else { return nil }
        return video
    }

    var isVideoProcessing: Bool {
        roomScanVideo != nil
    }

    private let designService: RoomDesignProviding?
    private let roomScanService: RoomScanSubmitting?
    private var processingTask: Task<Void, Never>?
    private var completionHandler: (@MainActor (RoomScene) -> Void)?

    init(
        room: SampleRoom,
        selectedPhoto: SelectedPhoto,
        designService: RoomDesignProviding
    ) {
        self.room = room
        input = .photo(selectedPhoto)
        self.designService = designService
        roomScanService = nil
        steps = [
            AnalysisStep(id: 0, title: "Uploading room"),
            AnalysisStep(id: 1, title: "Detecting walls"),
            AnalysisStep(id: 2, title: "Detecting furniture"),
            AnalysisStep(id: 3, title: "Estimating room geometry"),
            AnalysisStep(id: 4, title: "Building editable scene"),
            AnalysisStep(id: 5, title: "Preparing design workspace")
        ]
    }

    init(
        room: SampleRoom,
        roomScanVideo: RoomScanVideo,
        roomScanService: RoomScanSubmitting
    ) {
        self.room = room
        input = .video(roomScanVideo)
        designService = nil
        self.roomScanService = roomScanService
        steps = [
            AnalysisStep(id: 0, title: "Preparing video"),
            AnalysisStep(id: 1, title: "Extracting key frames"),
            AnalysisStep(id: 2, title: "Estimating camera movement"),
            AnalysisStep(id: 3, title: "Reconstructing room geometry"),
            AnalysisStep(id: 4, title: "Identifying walls and furniture"),
            AnalysisStep(id: 5, title: "Preparing editable workspace")
        ]
    }

    func start(onComplete: @escaping @MainActor (RoomScene) -> Void) {
        guard processingTask == nil else { return }
        completionHandler = onComplete
        beginProcessing()
    }

    func retry() {
        guard case .failed = analysisState,
              processingTask == nil,
              completionHandler != nil else { return }

        analysisProgress = 0
        completedStepCount = 0
        analysisState = .idle
        beginProcessing()
    }

    private func beginProcessing() {
        guard let completionHandler else { return }

        processingTask = Task {
            analysisState = .analyzing
            defer { processingTask = nil }

            do {
                let scene: RoomScene
                switch input {
                case .photo:
                    scene = try await processPhoto()
                case .video(let video):
                    scene = try await processVideo(video)
                }

                try Task.checkCancellation()
                withAnimation(.easeOut(duration: 0.3)) {
                    analysisProgress = 1
                    completedStepCount = steps.count
                    analysisState = .completed
                }
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                completionHandler(scene)
            } catch is CancellationError {
                return
            } catch {
                analysisState = .failed(error.localizedDescription)
            }
        }
    }

    private func processPhoto() async throws -> RoomScene {
        guard let designService else {
            throw ProcessingError.missingPhotoService
        }

        for index in steps.indices {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 520_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                completedStepCount = index + 1
                analysisProgress = Double(completedStepCount) / Double(steps.count)
            }
        }

        return try await designService.createScene(for: room)
    }

    private func processVideo(_ video: RoomScanVideo) async throws -> RoomScene {
        guard let roomScanService else {
            throw ProcessingError.missingRoomScanService
        }

        let accepted = try await roomScanService.submit(video)
        try await roomScanService.pollUntilCompleted(jobID: accepted.jobID) { [weak self] job in
            Task { @MainActor in
                self?.apply(jobProgress: job)
            }
        }

        let backendScene = try await roomScanService.fetchScene(jobID: accepted.jobID)
        return try BackendSceneAdapter.makeRoomScene(from: backendScene, jobID: accepted.jobID)
    }

    private func apply(jobProgress job: RoomScanJobResponse) {
        let boundedProgress = min(max(job.progress, 0), 1)
        let stageIndex: Int
        switch job.stage {
        case "queued", "preparing_video":
            stageIndex = 0
        case "extracting_key_frames":
            stageIndex = 1
        case "estimating_camera_motion":
            stageIndex = 2
        case "reconstructing_room_geometry":
            stageIndex = 3
        case "identifying_walls_and_furniture":
            stageIndex = 4
        case "preparing_editable_workspace":
            stageIndex = 5
        case "completed":
            stageIndex = steps.count
        default:
            stageIndex = min(Int(boundedProgress * Double(steps.count)), steps.count)
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            analysisProgress = boundedProgress
            completedStepCount = min(max(stageIndex, 0), steps.count)
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
    }
}

private enum ProcessingError: LocalizedError {
    case missingPhotoService
    case missingRoomScanService

    var errorDescription: String? {
        switch self {
        case .missingPhotoService:
            return "The photo processing service is unavailable."
        case .missingRoomScanService:
            return "The room scan service is unavailable."
        }
    }
}
