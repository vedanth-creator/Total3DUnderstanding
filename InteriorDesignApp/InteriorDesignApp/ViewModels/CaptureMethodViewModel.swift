import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class CaptureMethodViewModel: ObservableObject {
    @Published private(set) var isImportingVideo = false
    @Published var errorMessage: String?

    private let videoImporter: RoomVideoImporting

    init(videoImporter: RoomVideoImporting = LocalRoomVideoImportService()) {
        self.videoImporter = videoImporter
    }

    func importVideo(from item: PhotosPickerItem) async -> RoomScanVideo? {
        guard !isImportingVideo else { return nil }
        isImportingVideo = true
        errorMessage = nil
        defer { isImportingVideo = false }

        do {
            let video = try await videoImporter.importVideo(from: item)
            guard video.duration >= 10 else {
                try? FileManager.default.removeItem(at: video.localFileURL)
                errorMessage = "Choose a room video that is at least 10 seconds long."
                return nil
            }
            return video
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
