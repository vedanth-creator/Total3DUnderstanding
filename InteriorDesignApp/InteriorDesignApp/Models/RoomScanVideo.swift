import AVFoundation
import Foundation

enum RoomScanVideoSource: String, Hashable {
    case recorded
    case imported
}

struct RoomScanVideo: Identifiable, Hashable {
    let id: UUID
    let localFileURL: URL
    let duration: TimeInterval
    let pixelWidth: Int?
    let pixelHeight: Int?
    let creationDate: Date
    let source: RoomScanVideoSource
    let fileSizeBytes: Int64

    static func inspect(
        localFileURL: URL,
        source: RoomScanVideoSource,
        id: UUID = UUID(),
        creationDate: Date = Date()
    ) async throws -> RoomScanVideo {
        let asset = AVURLAsset(url: localFileURL)
        let assetDuration = try await asset.load(.duration)
        let seconds = assetDuration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw RoomScanVideoError.invalidDuration
        }

        var pixelWidth: Int?
        var pixelHeight: Int?
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let displayedSize = naturalSize.applying(preferredTransform)
            pixelWidth = Int(abs(displayedSize.width).rounded())
            pixelHeight = Int(abs(displayedSize.height).rounded())
        }

        let resourceValues = try localFileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ])
        let fileSize = resourceValues.fileSize ?? resourceValues.totalFileAllocatedSize ?? 0

        return RoomScanVideo(
            id: id,
            localFileURL: localFileURL,
            duration: seconds,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            creationDate: creationDate,
            source: source,
            fileSizeBytes: Int64(fileSize)
        )
    }
}

enum RoomScanVideoError: LocalizedError {
    case invalidDuration
    case unavailable
    case importFailed

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "The selected video does not contain a usable room scan."
        case .unavailable:
            "Video capture is unavailable on this device."
        case .importFailed:
            "The video could not be imported. Please try another one."
        }
    }
}
