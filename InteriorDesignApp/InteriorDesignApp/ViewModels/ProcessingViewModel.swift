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

    private let designService: RoomDesignProviding
    private var processingTask: Task<Void, Never>?

    init(
        room: SampleRoom,
        selectedPhoto: SelectedPhoto,
        designService: RoomDesignProviding
    ) {
        self.room = room
        input = .photo(selectedPhoto)
        self.designService = designService
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
        designService: RoomDesignProviding
    ) {
        self.room = room
        input = .video(roomScanVideo)
        self.designService = designService
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

        processingTask = Task {
            analysisState = .analyzing

            for index in steps.indices {
                guard !Task.isCancelled else { return }
                do {
                    try await Task.sleep(
                        nanoseconds: isVideoProcessing ? 600_000_000 : 520_000_000
                    )
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: 0.4)) {
                    completedStepCount = index + 1
                    analysisProgress = Double(completedStepCount) / Double(steps.count)
                }
            }

            guard !Task.isCancelled else { return }
            do {
                let scene = try await designService.createScene(for: room)
                withAnimation(.easeOut(duration: 0.3)) {
                    analysisState = .completed
                }
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                onComplete(scene)
            } catch {
                analysisState = .failed("We couldn’t prepare your room. Please try again.")
            }
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
    }
}
