import AVFoundation
import AVKit
import Foundation
import UIKit

@MainActor
final class VideoReviewViewModel: ObservableObject {
    let video: RoomScanVideo
    let player: AVPlayer

    @Published private(set) var thumbnail: UIImage?

    var durationText: String {
        let totalSeconds = Int(video.duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var detailsText: String {
        let dimensions: String
        if let width = video.pixelWidth, let height = video.pixelHeight {
            dimensions = "\(width) × \(height)"
        } else {
            dimensions = "Video"
        }
        return "\(dimensions) · \(ByteCountFormatter.string(fromByteCount: video.fileSizeBytes, countStyle: .file))"
    }

    init(video: RoomScanVideo) {
        self.video = video
        player = AVPlayer(url: video.localFileURL)
    }

    func preparePreview() async {
        guard thumbnail == nil else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video.localFileURL))
        generator.appliesPreferredTrackTransform = true
        do {
            let result = try await generator.image(at: CMTime(seconds: 0.25, preferredTimescale: 600))
            thumbnail = UIImage(cgImage: result.image)
        } catch {
            thumbnail = nil
        }
    }

    func pause() {
        player.pause()
    }

    func discardVideo() {
        player.pause()
        try? FileManager.default.removeItem(at: video.localFileURL)
    }
}
