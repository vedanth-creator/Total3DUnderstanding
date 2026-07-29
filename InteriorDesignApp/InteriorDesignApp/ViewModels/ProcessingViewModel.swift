import SwiftUI

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var stage = "Preparing your room"

    let room: SampleRoom

    private let designService: RoomDesignProviding
    private var processingTask: Task<Void, Never>?

    init(room: SampleRoom, designService: RoomDesignProviding) {
        self.room = room
        self.designService = designService
    }

    func start(onComplete: @escaping @MainActor (RoomScene) -> Void) {
        guard processingTask == nil else { return }

        processingTask = Task {
            let stages = [
                (0.18, "Reading room geometry"),
                (0.43, "Finding furniture"),
                (0.70, "Building your editable scene"),
                (0.92, "Polishing the preview")
            ]

            for (nextProgress, nextStage) in stages {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 430_000_000)
                withAnimation(.easeInOut(duration: 0.4)) {
                    progress = nextProgress
                    stage = nextStage
                }
            }

            guard !Task.isCancelled else { return }
            do {
                let scene = try await designService.createScene(for: room)
                withAnimation(.easeOut(duration: 0.3)) {
                    progress = 1.0
                    stage = "Ready"
                }
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                onComplete(scene)
            } catch {
                stage = "Unable to prepare this room"
            }
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
    }
}
